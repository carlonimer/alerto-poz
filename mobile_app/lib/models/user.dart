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
  final bool active;
  final bool idVerified;
  final String verificationStatus;
  final String? idType;
  final String? rejectionReason;
  final int? idSubmittedAt;
  final int? idReviewedAt;
  final bool termsAccepted;
  final String? termsAcceptedVersion;
  final int? termsAcceptedAt;
  final String? requiredTermsVersion;

  bool get isIdApproved =>
      type != 'citizen' ||
      (idVerified && verificationStatus.trim().toLowerCase() == 'approved');

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
    this.active = true,
    this.idVerified = true,
    this.verificationStatus = 'approved',
    this.idType,
    this.rejectionReason,
    this.idSubmittedAt,
    this.idReviewedAt,
    this.termsAccepted = false,
    this.termsAcceptedVersion,
    this.termsAcceptedAt,
    this.requiredTermsVersion,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final activeVal = json['active'];
    final isActive = activeVal == null ? true : (activeVal == 1 || activeVal == true);
    final rawVerStatus = (json['verification_status'] ?? json['id_verification_status'])?.toString();
    final effectiveVerStatus = rawVerStatus ?? (isActive ? 'approved' : 'unsubmitted');
    final isStatusApproved = effectiveVerStatus.trim().toLowerCase() == 'approved';
    final isIdVer = json['id_verified'] == null
        ? (isActive && isStatusApproved)
        : (json['id_verified'] == true || json['id_verified'] == 1);
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
      active: isActive,
      idVerified: isIdVer,
      verificationStatus: effectiveVerStatus,
      idType: (json['id_type'] ?? json['idType'])?.toString(),
      rejectionReason: (json['rejection_reason'] ?? json['rejectionReason'])?.toString(),
      idSubmittedAt: json['id_submitted_at'] is int
          ? json['id_submitted_at'] as int
          : int.tryParse((json['id_submitted_at'] ?? json['submittedAt'])?.toString() ?? ''),
      idReviewedAt: json['id_reviewed_at'] is int
          ? json['id_reviewed_at'] as int
          : int.tryParse((json['id_reviewed_at'] ?? json['reviewedAt'])?.toString() ?? ''),
      termsAccepted: json['terms_accepted'] == true || json['terms_accepted'] == 1,
      termsAcceptedVersion: json['terms_accepted_version']?.toString(),
      termsAcceptedAt: json['terms_accepted_at'] is int ? json['terms_accepted_at'] as int : int.tryParse(json['terms_accepted_at']?.toString() ?? ''),
      requiredTermsVersion: json['required_terms_version']?.toString(),
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
      'active': active ? 1 : 0,
      'id_verified': idVerified,
      'verification_status': verificationStatus,
      'id_type': idType,
      'rejection_reason': rejectionReason,
      'id_submitted_at': idSubmittedAt,
      'id_reviewed_at': idReviewedAt,
      'terms_accepted': termsAccepted,
      'terms_accepted_version': termsAcceptedVersion,
      'terms_accepted_at': termsAcceptedAt,
      'required_terms_version': requiredTermsVersion,
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
    bool? active,
    bool? idVerified,
    String? verificationStatus,
    String? idType,
    String? rejectionReason,
    bool clearRejectionReason = false,
    int? idSubmittedAt,
    int? idReviewedAt,
    bool? termsAccepted,
    String? termsAcceptedVersion,
    int? termsAcceptedAt,
    String? requiredTermsVersion,
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
      active: active ?? this.active,
      idVerified: idVerified ?? this.idVerified,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      idType: idType ?? this.idType,
      rejectionReason: clearRejectionReason ? null : (rejectionReason ?? this.rejectionReason),
      idSubmittedAt: idSubmittedAt ?? this.idSubmittedAt,
      idReviewedAt: idReviewedAt ?? this.idReviewedAt,
      termsAccepted: termsAccepted ?? this.termsAccepted,
      termsAcceptedVersion: termsAcceptedVersion ?? this.termsAcceptedVersion,
      termsAcceptedAt: termsAcceptedAt ?? this.termsAcceptedAt,
      requiredTermsVersion: requiredTermsVersion ?? this.requiredTermsVersion,
    );
  }
}
