import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser;
  List<UserModel> _allUsers = [];
  bool _isLoading = false;
  String? _errorMessage;

  UserModel? get currentUser => _currentUser;
  List<UserModel> get allUsers => _allUsers;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Helper to normalize phone numbers to email formats required by Firebase Auth
  String _normalizeEmail(String emailOrPhone) {
    if (emailOrPhone.contains('@')) {
      return emailOrPhone.trim();
    } else {
      return '${emailOrPhone.trim()}@roadaware.com';
    }
  }

  // Initialize session and preloaded users list from Firebase
  Future<void> initSession() async {
    _isLoading = true;
    notifyListeners();

    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(firebaseUser.uid).get();
        if (doc.exists && doc.data() != null) {
          _currentUser = UserModel.fromJson(doc.data()!);
        } else {
          // If Firestore document doesn't exist, create a fallback
          _currentUser = UserModel(
            id: firebaseUser.uid,
            fullName: firebaseUser.displayName ?? firebaseUser.email?.split('@')[0] ?? 'User',
            emailOrPhone: firebaseUser.email ?? 'no-email',
            password: 'Managed by Firebase Auth',
            isLoggedIn: true,
          );
        }
      } else {
        _currentUser = null;
      }
      await getUsers();
    } catch (e) {
      _errorMessage = 'Session initialization failed: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Get all users from Firestore
  Future<List<UserModel>> getUsers() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').get();
      _allUsers = snapshot.docs.map((doc) => UserModel.fromJson(doc.data())).toList();
      notifyListeners();
      return _allUsers;
    } catch (e) {
      return [];
    }
  }

  // Register user
  Future<bool> register(String fullName, String emailOrPhone, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final normalizedEmail = _normalizeEmail(emailOrPhone);
      
      // Register in Firebase Auth
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      final uid = userCredential.user!.uid;

      // Update user display name in Firebase Auth
      await userCredential.user!.updateDisplayName(fullName);

      // Create user profile in Firestore
      final newUser = UserModel(
        id: uid,
        fullName: fullName,
        emailOrPhone: emailOrPhone,
        password: 'Managed by Firebase Auth',
        isAdmin: false,
        isLoggedIn: false, // Registered users must log in
      );

      await FirebaseFirestore.instance.collection('users').doc(uid).set(newUser.toJson());
      await getUsers();

      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        _errorMessage = 'Email or Phone already registered.';
      } else {
        _errorMessage = e.message ?? 'Registration failed.';
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Registration failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Login user
  Future<bool> login(String emailOrPhone, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final normalizedEmail = _normalizeEmail(emailOrPhone);

    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      final uid = userCredential.user!.uid;
      
      // Fetch profile from Firestore
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      UserModel user;
      if (doc.exists && doc.data() != null) {
        user = UserModel.fromJson(doc.data()!).copyWith(isLoggedIn: true);
      } else {
        user = UserModel(
          id: uid,
          fullName: userCredential.user!.displayName ?? emailOrPhone.split('@')[0],
          emailOrPhone: emailOrPhone,
          password: 'Managed by Firebase Auth',
          isAdmin: emailOrPhone.contains('admin'), // Simple fallback
          isLoggedIn: true,
        );
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).set(user.toJson());
      _currentUser = user;
      await getUsers();

      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      // Dynamic Seeding fallback for demo credentials
      if (e.code == 'user-not-found' || e.code == 'invalid-credential' || e.code == 'wrong-password') {
        final success = await _checkAndSeedDemoUser(emailOrPhone, password);
        if (success) {
          _isLoading = false;
          notifyListeners();
          return true;
        }
      }
      _errorMessage = 'Invalid email/phone or password.';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Login failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Seed demo user helper if they don't exist yet on live firebase instance
  Future<bool> _checkAndSeedDemoUser(String emailOrPhone, String password) async {
    bool isDemo = false;
    String fullName = '';
    bool isAdmin = false;

    if (emailOrPhone == 'admin@roadaware.com' && password == 'admin123') {
      isDemo = true;
      fullName = 'System Admin';
      isAdmin = true;
    } else if (emailOrPhone == 'taha@roadaware.com' && password == 'taha123') {
      isDemo = true;
      fullName = 'Muhammad Taha';
      isAdmin = false;
    } else if (emailOrPhone == 'ali@roadaware.com' && password == 'ali123') {
      isDemo = true;
      fullName = 'Ali Ahmed';
      isAdmin = false;
    }

    if (!isDemo) return false;

    try {
      // Create user in Firebase Auth
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailOrPhone,
        password: password,
      );
      final uid = userCredential.user!.uid;
      await userCredential.user!.updateDisplayName(fullName);

      // Create document in Firestore
      final seedUser = UserModel(
        id: uid,
        fullName: fullName,
        emailOrPhone: emailOrPhone,
        password: 'Managed by Firebase Auth',
        isAdmin: isAdmin,
        isLoggedIn: true,
      );

      await FirebaseFirestore.instance.collection('users').doc(uid).set(seedUser.toJson());
      _currentUser = seedUser;
      await getUsers();
      return true;
    } catch (e) {
      // If user creation fails because they already exist, try to sign in
      try {
        final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailOrPhone,
          password: password,
        );
        final uid = userCredential.user!.uid;
        
        final seedUser = UserModel(
          id: uid,
          fullName: fullName,
          emailOrPhone: emailOrPhone,
          password: 'Managed by Firebase Auth',
          isAdmin: isAdmin,
          isLoggedIn: true,
        );
        await FirebaseFirestore.instance.collection('users').doc(uid).set(seedUser.toJson());
        _currentUser = seedUser;
        await getUsers();
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  // Change password
  Future<bool> changePassword(String currentPassword, String newPassword) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentUser == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Reauthenticate user before changing password
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);

      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') {
        _errorMessage = 'Current password is incorrect.';
      } else {
        _errorMessage = e.message ?? 'Failed to change password.';
      }
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Failed to change password: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Logout session
  Future<void> logout() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // Mark as offline in Firestore
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data() != null) {
          final updatedUser = UserModel.fromJson(doc.data()!).copyWith(isLoggedIn: false);
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(updatedUser.toJson());
        }
      } catch (_) {}
    }
    
    await FirebaseAuth.instance.signOut();
    _currentUser = null;
    await getUsers();
    notifyListeners();
  }
}

