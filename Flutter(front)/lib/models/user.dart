class User {
  final int id;
  final String email;
  final String? fullName;
  final bool isActive;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.email,
    this.fullName,
    required this.isActive,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        email: json['email'] as String,
        fullName: json['full_name'] as String?,
        isActive: json['is_active'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  String get displayName => fullName?.isNotEmpty == true ? fullName! : email;
}
