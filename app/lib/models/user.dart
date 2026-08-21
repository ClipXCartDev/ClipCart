class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.age,
    this.gender,
    this.nationality,
  });

  final String id;
  final String name;
  final String email;
  final String role; // customer | editor | admin
  final int? age;
  final String? gender;
  final String? nationality;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String,
        role: j['role'] as String,
        age: (j['age'] as num?)?.toInt(),
        gender: j['gender'] as String?,
        nationality: j['nationality'] as String?,
      );

  bool get isEditor => role == 'editor' || role == 'admin';
}
