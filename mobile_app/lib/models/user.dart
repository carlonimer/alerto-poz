class UserModel {
  final int id;
  final String name;
  final String phone;
  final String email;
  final String type; // 'citizen' | 'authority'
  final String profileImage;
  final String firstName;
  final String lastName;
  final String middleName;
  final String suffix;
  final String birthdate;
  final String address;
  final bool hasPasscode;
  final String gender;
  final String passcode; // "SET" flag from web
  final Map<String, dynamic>? mapSettings;

  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.type,
    this.profileImage = '',
    this.firstName = '',
    this.lastName = '',
    this.middleName = '',
    this.suffix = '',
    this.birthdate = '',
    this.address = '',
    this.hasPasscode = false,
    this.gender = '',
    this.passcode = '',
    this.mapSettings,
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
      middleName: json['middle_name'] as String? ?? '',
      suffix: json['suffix'] as String? ?? '',
      birthdate: json['birthdate'] as String? ?? '',
      address: json['address'] as String? ?? '',
      hasPasscode: json['hasPasscode'] == true || json['passcode'] == 'SET',
      gender: json['gender'] as String? ?? '',
      passcode: json['passcode'] as String? ?? '',
      mapSettings: json['map_settings'] as Map<String, dynamic>?,
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
      'middle_name': middleName,
      'suffix': suffix,
      'birthdate': birthdate,
      'address': address,
      'hasPasscode': hasPasscode,
      'gender': gender,
      'passcode': passcode,
      'map_settings': mapSettings,
    };
  }

  /// Returns a copy with updated fields (for profile-updated socket event)
  UserModel copyWith({
    int? id,
    String? name,
    String? phone,
    String? email,
    String? type,
    String? profileImage,
    String? firstName,
    String? lastName,
    String? middleName,
    String? suffix,
    String? birthdate,
    String? address,
    bool? hasPasscode,
    String? gender,
    String? passcode,
    Map<String, dynamic>? mapSettings,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      type: type ?? this.type,
      profileImage: profileImage ?? this.profileImage,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      middleName: middleName ?? this.middleName,
      suffix: suffix ?? this.suffix,
      birthdate: birthdate ?? this.birthdate,
      address: address ?? this.address,
      hasPasscode: hasPasscode ?? this.hasPasscode,
      gender: gender ?? this.gender,
      passcode: passcode ?? this.passcode,
      mapSettings: mapSettings ?? this.mapSettings,
    );
  }
}
