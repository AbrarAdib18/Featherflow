"""Delivery-location validation shared by checkout flows (NF-3)."""

# Bangladesh bounding box (generous): lat 20.5-26.7, lng 88.0-92.8.
BD_LAT = (20.5, 26.7)
BD_LNG = (88.0, 92.8)


class LocationError(ValueError):
    def __init__(self, code, detail):
        super().__init__(detail)
        self.code = code
        self.detail = detail


def parse_location(lat, lng, *, required=True):
    """Return (lat, lng) floats, or (None, None) when optional and absent.

    Raises LocationError(code, detail) for: missing (required), non-numeric,
    NaN/inf, out of range, or outside Bangladesh.
    """
    if lat in (None, '') and lng in (None, ''):
        if required:
            raise LocationError('delivery_location_required',
                                'A delivery location (latitude/longitude) is required.')
        return None, None
    if lat in (None, '') or lng in (None, ''):
        raise LocationError('delivery_location_incomplete', 'Both latitude and longitude are required.')
    try:
        la, lo = float(lat), float(lng)
    except (TypeError, ValueError):
        raise LocationError('delivery_location_invalid', 'latitude/longitude must be numeric.')
    if la != la or lo != lo or abs(la) == float('inf') or abs(lo) == float('inf'):
        raise LocationError('delivery_location_invalid', 'latitude/longitude must be finite numbers.')
    if not (-90 <= la <= 90 and -180 <= lo <= 180):
        raise LocationError('delivery_location_invalid', 'latitude/longitude are out of range.')
    if not (BD_LAT[0] <= la <= BD_LAT[1] and BD_LNG[0] <= lo <= BD_LNG[1]):
        raise LocationError('delivery_location_outside_service_area',
                            'This location is outside the Bangladesh delivery area.')
    return round(la, 6), round(lo, 6)
