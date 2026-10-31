"""Shared helpers for scripts that drive a delivery through the F-005
lifecycle (arrived -> proof submitted -> admin approval -> delivered)."""
from django.core.files.uploadedfile import SimpleUploadedFile

JSON = 'application/json'
PNG = bytes.fromhex(
    '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4'
    '890000000a49444154789c6360000002000100b3a8e2760000000049454e44ae'
    '426082'
)


def png_file(name='proof.png'):
    return SimpleUploadedFile(name, PNG, content_type='image/png')


def arrive(rc, order_id):
    return rc.patch(f'/api/delivery/orders/{order_id}/status/', {'status': 'arrived'}, content_type=JSON)


def submit_proof(rc, order_id, otp=None, note=''):
    data = {'file': png_file(), 'note': note}
    if otp:
        data['otp_code'] = otp
    return rc.post(f'/api/delivery/orders/{order_id}/proof/', data)


def approve(admin_client, proof_id):
    return admin_client.post(f'/api/admin-panel/delivery-proofs/{proof_id}/approve/', {}, content_type=JSON)


def reject(admin_client, proof_id, reason):
    return admin_client.post(f'/api/admin-panel/delivery-proofs/{proof_id}/reject/', {'reason': reason}, content_type=JSON)


def complete_delivery(rc, admin_client, order_id, otp=None):
    """on_the_way -> arrived -> proof submitted -> admin approves. Returns the
    approval response."""
    r = arrive(rc, order_id)
    assert r.status_code == 200, r.content[:300]
    r = submit_proof(rc, order_id, otp=otp)
    assert r.status_code == 201, r.content[:300]
    return approve(admin_client, r.json()['proof']['id'])
