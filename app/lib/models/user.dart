class AppUser {
  AppUser({required this.id, required this.name, required this.email, required this.role});

  final String id;
  final String name;
  final String email;
  final String role; // customer | editor | admin

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String,
        role: j['role'] as String,
      );

  bool get isEditor => role == 'editor' || role == 'admin';
}
