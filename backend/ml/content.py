"""Curated reference content for every class the disease-detection model can
predict.

The trained EfficientNet checkpoint (``ML/checkpoints/final_model.pth``)
outputs raw class names (14 for the current EfficientNet-b0 model, 15 for the
older b3 model). They are messy (mixed case, historically two "healthy" folders
from the merged training set), so each raw label is mapped here to:

* ``label``                  - clean display name
* ``severity``               - one of low / medium / high / critical  (None = healthy)
* ``requires_immediate_vet`` - show the "book a vet now" urgency
* ``notifiable``             - reportable to veterinary authorities in most regions
* ``description``            - one or two plain sentences
* ``symptoms`` / ``what_to_do`` / ``what_not_to_do`` / ``prevention`` - short lists

This is **general first-aid guidance, not a diagnosis** - the API always tells
the farmer to confirm with a vet.
"""

HEALTHY_KEYS = {'HEALTHY', 'Healthy Chicken'}

# raw model label -> metadata
CLASS_META = {
    'HEALTHY': {
        'label': 'Healthy', 'severity': None, 'requires_immediate_vet': False,
        'notifiable': False,
        'description': 'No signs of disease detected in this image. Keep monitoring the flock.',
        'symptoms': [],
        'what_to_do': [
            'Continue daily flock checks and keep records of feed, water and mortality.',
            'Maintain the vaccination schedule your vet recommended.',
            'Keep housing dry, well ventilated and at the right temperature for the birds\' age.',
        ],
        'what_not_to_do': [
            'Don\'t treat birds with antibiotics or other medicines "just in case".',
            'Don\'t relax biosecurity - most outbreaks start with a healthy-looking flock.',
        ],
        'prevention': [
            'Restrict farm visitors and disinfect footwear at the entrance.',
            'Quarantine new or returning birds for 2-3 weeks.',
            'Control rodents and wild birds around the sheds.',
        ],
    },
    'Healthy Chicken': None,  # filled in below (alias of HEALTHY)

    'Anemia Virus': {
        'label': 'Chicken Infectious Anaemia', 'severity': 'high',
        'requires_immediate_vet': True, 'notifiable': False,
        'description': 'A viral disease (CIAV) that destroys blood and immune cells in young chicks, '
                       'leaving them weak and prone to other infections.',
        'symptoms': [
            'Pale comb, wattles and skin', 'Weakness, huddling and poor growth',
            'Higher chick mortality in the 2-4 week age range',
            'Blue-tinged wingtips or skin haemorrhages',
        ],
        'what_to_do': [
            'Isolate affected chicks and keep them warm and hydrated.',
            'Contact a vet - secondary infections often need treatment.',
            'Review the breeder flock\'s CIAV vaccination status.',
        ],
        'what_not_to_do': [
            'Don\'t mix affected chicks with older healthy birds.',
            'Don\'t reuse brooder litter without a full clean-out and disinfection.',
        ],
        'prevention': [
            'Source chicks from CIAV-vaccinated breeder flocks.',
            'Strict all-in / all-out management with cleaning between batches.',
        ],
    },
    'Avian Influenza': {
        'label': 'Avian Influenza (Bird Flu)', 'severity': 'critical',
        'requires_immediate_vet': True, 'notifiable': True,
        'description': 'A highly contagious viral disease. Some strains cause very high, sudden '
                       'mortality and can infect people. It is legally reportable in most countries.',
        'symptoms': [
            'Sudden death of many birds with few prior signs',
            'Swollen, blue/purple head, comb and wattles',
            'Severe drop in egg production', 'Coughing, sneezing, nasal discharge',
            'Green diarrhoea, lack of coordination',
        ],
        'what_to_do': [
            'Stop all bird and egg movement on and off the farm immediately.',
            'Report to your local veterinary / livestock authority the same day.',
            'Keep everyone out of the sheds except essential, protected staff.',
        ],
        'what_not_to_do': [
            'Don\'t sell, slaughter or move sick or in-contact birds.',
            'Don\'t visit other poultry farms until cleared by authorities.',
            'Don\'t handle sick birds without a mask, gloves and eye protection.',
        ],
        'prevention': [
            'Keep poultry away from wild waterfowl and open water.',
            'Netting over runs; no shared equipment with other farms.',
            'Strict visitor control and footbaths at every entrance.',
        ],
    },
    'Botulism': {
        'label': 'Botulism', 'severity': 'high',
        'requires_immediate_vet': True, 'notifiable': False,
        'description': 'Poisoning by a toxin from decaying carcasses, maggots or spoiled feed. '
                       'It causes progressive paralysis.',
        'symptoms': [
            'Progressive limp paralysis - legs, then wings, then neck ("limberneck")',
            'Birds sitting with head on the ground',
            'Ruffled feathers that pull out easily', 'Sudden deaths near a common source',
        ],
        'what_to_do': [
            'Remove and safely dispose of all carcasses, rotting matter and suspect feed now.',
            'Move birds to clean ground with fresh water.',
            'Call a vet - antitoxin and supportive care may help early cases.',
        ],
        'what_not_to_do': [
            'Don\'t leave dead birds in or near the run.',
            'Don\'t let birds access stagnant ponds or wet, decaying litter.',
        ],
        'prevention': [
            'Collect dead birds daily; control flies and maggots.',
            'Store feed dry; discard mouldy or wet feed.',
        ],
    },
    'Bumblefoot': {
        'label': 'Bumblefoot (Foot-pad Dermatitis)', 'severity': 'medium',
        'requires_immediate_vet': False, 'notifiable': False,
        'description': 'A localised bacterial infection of the foot pad, usually from a cut, splinter '
                       'or constant pressure on hard or wet flooring.',
        'symptoms': [
            'Swollen foot pad, often with a dark scab', 'Limping or reluctance to walk',
            'Heat and redness around the pad', 'In bad cases, swelling up the leg',
        ],
        'what_to_do': [
            'Move the bird to soft, clean, dry bedding.',
            'Gently clean the foot with warm salt water or dilute antiseptic.',
            'Have a vet assess whether the abscess needs draining or antibiotics.',
        ],
        'what_not_to_do': [
            'Don\'t cut into the foot yourself - it can drive infection deeper.',
            'Don\'t return the bird to wet litter or wire flooring.',
        ],
        'prevention': [
            'Keep perches smooth and litter dry and deep.',
            'Check for and remove sharp objects in the run.',
        ],
    },
    'COCCIDIOSIS': {
        'label': 'Coccidiosis', 'severity': 'high',
        'requires_immediate_vet': False, 'notifiable': False,
        'description': 'A very common gut-parasite disease, worst in warm, damp litter. It damages '
                       'the intestine and can kill young birds quickly.',
        'symptoms': [
            'Blood or mucus in droppings', 'Ruffled feathers, huddling, pale comb',
            'Drop in feed and water intake', 'Slow growth and rising mortality in growers',
        ],
        'what_to_do': [
            'Start an approved anticoccidial in the water as soon as possible.',
            'Remove wet, caked litter and keep bedding dry.',
            'Support recovery with vitamins A and K and electrolytes.',
        ],
        'what_not_to_do': [
            'Don\'t ignore early blood in droppings - losses climb fast.',
            'Don\'t let drinkers leak onto the litter.',
        ],
        'prevention': [
            'Keep litter dry; avoid overcrowding.',
            'Use a coccidiosis vaccine or in-feed coccidiostat as your vet advises.',
        ],
    },
    'Fowl Cholera': {
        'label': 'Fowl Cholera (Pasteurellosis)', 'severity': 'high',
        'requires_immediate_vet': True, 'notifiable': False,
        'description': 'A bacterial disease (Pasteurella multocida) that can cause sudden deaths in '
                       'the acute form and swollen joints and wattles in the chronic form.',
        'symptoms': [
            'Sudden deaths in birds that looked healthy',
            'Purple comb and wattles, fever, ruffled feathers',
            'Yellowish or greenish diarrhoea', 'Later: swollen wattles, lameness, twisted neck',
        ],
        'what_to_do': [
            'Isolate sick birds and get a vet diagnosis - it responds to specific antibiotics.',
            'Remove carcasses promptly and disinfect drinkers and feeders.',
            'Control rodents, which spread the bacteria.',
        ],
        'what_not_to_do': [
            'Don\'t add new birds to an affected flock.',
            'Don\'t rely on home remedies - untreated flocks keep losing birds.',
        ],
        'prevention': [
            'Rodent and wild-bird control; clean water lines.',
            'Vaccinate in areas where the disease is common.',
        ],
    },
    'Fowl pox': {
        'label': 'Fowl Pox', 'severity': 'medium',
        'requires_immediate_vet': False, 'notifiable': False,
        'description': 'A slow-spreading viral disease, often carried by mosquitoes. The dry form '
                       'causes wart-like scabs on the skin; the wet form affects the mouth and airway.',
        'symptoms': [
            'Raised grey-to-dark scabs on comb, wattles and around the eyes (dry form)',
            'Yellow cheesy patches in the mouth or throat (wet form)',
            'Reduced feeding, drop in egg production',
        ],
        'what_to_do': [
            'Isolate affected birds; most recover from the dry form in 2-4 weeks.',
            'Keep feed and water easy to reach; add vitamins.',
            'See a vet for wet-form cases - birds can suffocate.',
        ],
        'what_not_to_do': [
            'Don\'t pick off scabs - it spreads the virus and causes bleeding.',
            'Don\'t vaccinate a flock that is already in an active outbreak without vet advice.',
        ],
        'prevention': [
            'Mosquito control - remove standing water, use screens.',
            'Vaccinate replacement pullets where fowl pox is common.',
        ],
    },
    'Mareks': {
        'label': "Marek\'s Disease", 'severity': 'high',
        'requires_immediate_vet': True, 'notifiable': False,
        'description': 'A herpesvirus that causes tumours and nerve damage, usually in birds 6-30 '
                       'weeks old. There is no cure; prevention is by vaccinating chicks at hatch.',
        'symptoms': [
            'Progressive leg or wing paralysis - classic "one leg forward, one back" pose',
            'Grey or irregular iris, poor vision', 'Weight loss despite eating, pale comb',
            'Sudden deaths in young growing birds',
        ],
        'what_to_do': [
            'Isolate paralysed or wasting birds and cull humanely if they cannot reach feed and water.',
            'Have a vet confirm the diagnosis (it looks like other paralysing diseases).',
            'Check that your hatchery vaccinates chicks against Marek\'s.',
        ],
        'what_not_to_do': [
            'Don\'t breed from or keep survivors as they stay infectious for life.',
            'Don\'t bring older unvaccinated birds onto the site.',
        ],
        'prevention': [
            'Vaccinate every chick at day-old at the hatchery.',
            'All-in / all-out; thorough clean-out of dust between flocks (the virus lives in dander).',
        ],
    },
    'NEW CASTLE': {
        'label': 'Newcastle Disease', 'severity': 'critical',
        'requires_immediate_vet': True, 'notifiable': True,
        'description': 'A highly contagious viral disease. Virulent strains cause very high mortality '
                       'with breathing, gut and nervous signs, and are legally reportable.',
        'symptoms': [
            'Gasping, coughing, sneezing and nasal discharge',
            'Greenish watery diarrhoea', 'Twisted neck, circling, paralysis, tremors',
            'Sharp drop or complete stop in egg production; thin-shelled eggs',
            'Swelling around the eyes and neck',
        ],
        'what_to_do': [
            'Stop all movement of birds, eggs and equipment off the farm.',
            'Report to the local veterinary authority immediately - it is notifiable.',
            'Isolate the shed and limit access to essential protected staff only.',
        ],
        'what_not_to_do': [
            'Don\'t sell or slaughter sick or in-contact birds.',
            'Don\'t visit or receive visitors from other poultry farms.',
        ],
        'prevention': [
            'Follow a strict Newcastle vaccination programme (e.g. day 7, booster day 21, then regularly).',
            'Strong biosecurity: visitor control, footbaths, no shared equipment.',
        ],
    },
    'Salmonella': {
        'label': 'Salmonellosis', 'severity': 'high',
        'requires_immediate_vet': True, 'notifiable': True,
        'description': 'Bacterial infection that can cause chick deaths and, importantly, can pass to '
                       'people through eggs and meat. Some serotypes are officially controlled.',
        'symptoms': [
            'High mortality in the first 1-2 weeks of life',
            'Chicks huddling near heat, eyes closed, pasted vents',
            'White or greenish diarrhoea, poor growth',
            'In layers: often no signs but contaminated eggs',
        ],
        'what_to_do': [
            'Isolate affected birds and improve chick warmth, hygiene and water quality.',
            'Have a vet take samples - treatment and control depend on the serotype.',
            'Handle birds and eggs with gloves and wash hands well.',
        ],
        'what_not_to_do': [
            'Don\'t sell eggs or meat from an affected flock until cleared.',
            'Don\'t eat undercooked eggs or meat from the flock.',
        ],
        'prevention': [
            'Buy chicks from Salmonella-monitored hatcheries.',
            'Rodent control, clean water, and cleaning/disinfection between flocks.',
        ],
    },
    'Vent Gleet': {
        'label': 'Vent Gleet (Cloacitis)', 'severity': 'medium',
        'requires_immediate_vet': False, 'notifiable': False,
        'description': 'An inflammation of the vent, often linked to a yeast (Candida) overgrowth, '
                       'stress, or a poor-quality diet.',
        'symptoms': [
            'Pasty, smelly white or yellow discharge around the vent',
            'Soiled, matted feathers below the vent', 'Reddened, swollen vent; straining',
            'Drop in laying, general dullness',
        ],
        'what_to_do': [
            'Gently clean the vent area with warm water and dry it.',
            'Improve diet quality and provide clean water; reduce stressors.',
            'See a vet if it does not improve in a few days or the bird is weak - an antifungal may be needed.',
        ],
        'what_not_to_do': [
            'Don\'t give broad-spectrum antibiotics - they can make a yeast problem worse.',
            'Don\'t ignore it; the vent can become badly infected.',
        ],
        'prevention': [
            'Balanced ration, clean drinkers, dry bedding.',
            'Avoid sudden feed changes and overcrowding.',
        ],
    },
    'coryza': {
        'label': 'Infectious Coryza', 'severity': 'medium',
        'requires_immediate_vet': True, 'notifiable': False,
        'description': 'A bacterial respiratory disease (Avibacterium paragallinarum) that spreads '
                       'fast, with a characteristic bad smell and facial swelling.',
        'symptoms': [
            'Swollen face and wattles, especially around the eyes',
            'Sticky nasal discharge with a foul smell', 'Sneezing, laboured breathing',
            'Eyes partly or fully closed; drop in egg production',
        ],
        'what_to_do': [
            'Isolate sick birds; get a vet diagnosis - it responds to specific antibiotics / sulfa drugs.',
            'Improve ventilation and reduce ammonia and dust.',
            'Treat the whole affected group, not just visibly sick birds.',
        ],
        'what_not_to_do': [
            'Don\'t add new birds - carriers stay infectious for months.',
            'Don\'t keep recovered birds as breeders or sell them as layers.',
        ],
        'prevention': [
            'All-in / all-out; do not mix age groups.',
            'Vaccinate in regions where coryza is endemic.',
        ],
    },
    'crd': {
        'label': 'Chronic Respiratory Disease (CRD / Mycoplasma)', 'severity': 'medium',
        'requires_immediate_vet': True, 'notifiable': False,
        'description': 'A slow, long-lasting respiratory disease caused by Mycoplasma, often made '
                       'worse by poor ventilation, dust, ammonia or a co-infection.',
        'symptoms': [
            'Persistent coughing, sneezing and rattling ("snick")',
            'Nasal and eye discharge, foamy eyes', 'Slow growth, poor feed conversion',
            'Gradual drop in egg production',
        ],
        'what_to_do': [
            'Improve air quality first: ventilation, dry litter, lower stocking density.',
            'Get a vet diagnosis - targeted antibiotics can control (not cure) it.',
            'Reduce other stressors and control any co-infections.',
        ],
        'what_not_to_do': [
            'Don\'t breed from infected birds - Mycoplasma passes through the egg.',
            'Don\'t expect a one-off treatment to clear it; it is a flock-management problem.',
        ],
        'prevention': [
            'Buy from Mycoplasma-clean (MG/MS-free) breeder stock.',
            'Good ventilation, all-in / all-out, and cleaning between flocks.',
        ],
    },
}
CLASS_META['Healthy Chicken'] = CLASS_META['HEALTHY']

# The retrained EfficientNet-b0 checkpoint (ML V1, swapped in 2026-09-10) uses a
# few renamed raw labels and drops the duplicate "Healthy Chicken" folder. Map
# the new names onto the same metadata so no advice content is lost.
CLASS_META['Botulism Disease'] = CLASS_META['Botulism']
CLASS_META['Mareks disease'] = CLASS_META['Mareks']

# Fallback advice when confidence is too low to name a disease.
UNCERTAIN = {
    'label': 'Uncertain',
    'severity': 'medium',
    'requires_immediate_vet': True,
    'notifiable': False,
    'description': 'The model could not identify the condition with enough confidence from this '
                   'image. This is common with blurry, dark or partial photos.',
    'symptoms': [],
    'what_to_do': [
        'Take another photo in good light, filling the frame with the affected bird or area.',
        'Isolate any birds showing symptoms and keep clean water available.',
        'Book a vet consultation for a proper diagnosis.',
    ],
    'what_not_to_do': [
        'Don\'t start medication based on a guess.',
        'Don\'t delay if birds are dying or clearly distressed - contact a vet now.',
    ],
    'prevention': [
        'Keep good daily records of feed, water, eggs and mortality to help the vet.',
    ],
}

# disease_scans.severity_level CHECK ('low','medium','high','critical') - map ours.
DB_SEVERITY = {None: None, 'low': 'low', 'medium': 'medium', 'high': 'high', 'critical': 'critical'}


# clean display label -> metadata (for looking up a saved scan\'s disease name)
CLASS_META_BY_LABEL = {
    meta['label']: meta for meta in CLASS_META.values() if meta is not None
}


def meta_for(raw_label):
    """Look up by the model\'s raw class name."""
    return CLASS_META.get(raw_label, UNCERTAIN)


def meta_by_label(label):
    """Look up by the clean display label (e.g. a stored `diseases.name`)."""
    return CLASS_META_BY_LABEL.get(label)


def is_healthy(raw_label):
    return raw_label in HEALTHY_KEYS
