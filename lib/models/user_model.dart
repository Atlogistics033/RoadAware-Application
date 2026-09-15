class UserModel {
  final String id;
  final String fullName;
  final String emailOrPhone;
  final String password;
  final bool isAdmin;
  final bool isLoggedIn;
  final String? profilePicture; // Base64 encoded profile image

  UserModel({
    required this.id,
    required this.fullName,
    required this.emailOrPhone,
    required this.password,
    this.isAdmin = false,
    this.isLoggedIn = false,
    this.profilePicture,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fullName': fullName,
        'emailOrPhone': emailOrPhone,
        'password': password,
        'isAdmin': isAdmin,
        'isLoggedIn': isLoggedIn,
        'profilePicture': profilePicture,
      };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'],
        fullName: json['fullName'],
        emailOrPhone: json['emailOrPhone'],
        password: json['password'],
        isAdmin: json['isAdmin'] ?? false,
        isLoggedIn: json['isLoggedIn'] ?? false,
        profilePicture: json['profilePicture'],
      );

  UserModel copyWith({
    String? id,
    String? fullName,
    String? emailOrPhone,
    String? password,
    bool? isAdmin,
    bool? isLoggedIn,
    String? profilePicture,
  }) {
    return UserModel(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      emailOrPhone: emailOrPhone ?? this.emailOrPhone,
      password: password ?? this.password,
      isAdmin: isAdmin ?? this.isAdmin,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      profilePicture: profilePicture ?? this.profilePicture,
    );
  }
}
