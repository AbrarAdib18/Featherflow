class AdminUserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String status;
  final String location;
  final String joined;
  final String lastActive;
  final bool verified;
  final String bio;

  const AdminUserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    required this.location,
    required this.joined,
    required this.lastActive,
    required this.verified,
    required this.bio,
  });

  factory AdminUserModel.fromJson(Map<String, dynamic> json) => AdminUserModel(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        role: json['role']?.toString() ?? 'Farmer',
        status: json['status']?.toString() ?? 'Pending',
        location: json['location']?.toString() ?? '',
        joined: json['joined']?.toString() ?? '',
        lastActive: json['last_active']?.toString() ?? '',
        verified: json['verified'] == true,
        bio: json['bio']?.toString() ?? '',
      );

  AdminUserModel copyWith({String? status}) => AdminUserModel(
        id: id,
        name: name,
        email: email,
        phone: phone,
        role: role,
        status: status ?? this.status,
        location: location,
        joined: joined,
        lastActive: lastActive,
        verified: verified,
        bio: bio,
      );
}

const kAdminUsers = <AdminUserModel>[
  AdminUserModel(
    id: 'U001',
    name: 'Karim Hossain',
    email: 'karim@farm.com',
    phone: '+880 1711-234567',
    role: 'Farmer',
    status: 'Approved',
    location: 'Dhaka, Bangladesh',
    joined: 'Jan 12, 2024',
    lastActive: '2 hours ago',
    verified: true,
    bio:
        'Experienced poultry farmer managing a 5,000-bird broiler operation in Dhaka.',
  ),
  AdminUserModel(
    id: 'U002',
    name: 'Dr. Rina Begum',
    email: 'rina@vetclinic.com',
    phone: '+880 1812-345678',
    role: 'Doctor',
    status: 'Pending',
    location: 'Chittagong, Bangladesh',
    joined: 'Feb 03, 2024',
    lastActive: '1 day ago',
    verified: false,
    bio:
        'Veterinary doctor specializing in avian diseases with 8 years of clinical experience.',
  ),
  AdminUserModel(
    id: 'U003',
    name: 'Rahim Uddin',
    email: 'rahim@rider.com',
    phone: '+880 1912-456789',
    role: 'Delivery',
    status: 'Approved',
    location: 'Dhaka, Bangladesh',
    joined: 'Mar 08, 2024',
    lastActive: '30 minutes ago',
    verified: true,
    bio:
        'Full-time delivery rider covering Dhaka metropolitan area with a 4.8-star rating.',
  ),
  AdminUserModel(
    id: 'U004',
    name: 'Sumaiya Islam',
    email: 'sumaiya@research.edu',
    phone: '+880 1612-567890',
    role: 'Researcher',
    status: 'Approved',
    location: 'Sylhet, Bangladesh',
    joined: 'Apr 01, 2024',
    lastActive: '3 hours ago',
    verified: true,
    bio:
        'Agricultural researcher at BRAC University focused on poultry disease prevention.',
  ),
  AdminUserModel(
    id: 'U005',
    name: 'MedPlus Rx',
    email: 'contact@medplusrx.com',
    phone: '+880 1511-678901',
    role: 'Pharmacy',
    status: 'Suspended',
    location: 'Rajshahi, Bangladesh',
    joined: 'May 20, 2024',
    lastActive: '5 days ago',
    verified: true,
    bio:
        'Licensed veterinary pharmacy supplying medicines and supplements to poultry farmers.',
  ),
  AdminUserModel(
    id: 'U006',
    name: 'Jamal Mia',
    email: 'jamal@layerfarm.com',
    phone: '+880 1411-789012',
    role: 'Farmer',
    status: 'Pending',
    location: 'Comilla, Bangladesh',
    joined: 'Jun 05, 2024',
    lastActive: '2 days ago',
    verified: false,
    bio:
        'New farmer with a 200-bird layer operation looking to scale up production.',
  ),
];
