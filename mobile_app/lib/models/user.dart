class UserModel {
  final int id;
  final String name;
  final String phone;
  final String email;
  final String type; // 'citizen' | 'authority'
  final String profileImage;
  final String firstName;
  final String lastName;
  final String address;

  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.type,
    this.profileImage = '',
    this.firstName = '',
    this.lastName = '',
    this.address = '',
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      type: json['role'] as String? ?? json['type'] as String? ?? 'citizen',
      profileImage: json['profile_image'] as String? ?? '',
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      address: json['address'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'type': type,
      'profile_image': profileImage,
      'first_name': firstName,
      'last_name': lastName,
      'address': address,
    };
  }
}
