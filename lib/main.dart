// =====================================================================
// المشروع الكامل: سوق سوريا الشامل (جميع الملفات المدمجة بدون أي نقص)
// =====================================================================

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------
// 1. AppConfig & Constants
// ---------------------------------------------------------------------
class AppConfig {
  static const String appName = 'سوق سوريا الشامل';
  static const Color primaryColor = Color(0xFF2D6A4F);
  static const Color secondaryColor = Color(0xFFD97706);
  static const Color backgroundColor = Color(0xFFF4F6F8);
  static const Color surfaceColor = Colors.white;
  static const Color errorColor = Color(0xFFDC2626);
  static const Color textPrimaryColor = Color(0xFF1F2937);
  static const Color textSecondaryColor = Color(0xFF6B7280);
  static const Color dividerColor = Color(0xFFE5E7EB);
  static const String supabaseUrl = 'https://zbjjkigkxbpktpmpcdqc.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_ZZBI_vTK7ks1yfO2g3Zo0Q_Sg4QizEr';
  static const String adsImagesBucket = 'ads-images';
}

class AppRoutes {
  static const String login = '/login';
  static const String signup = '/signup';
  static const String home = '/home';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case signup:
        return MaterialPageRoute(builder: (_) => const SignupScreen());
      case home:
        // شاشة الرئيسية الافتراضية أو قائمة المحادثات
        return MaterialPageRoute(builder: (_) => const ConversationsListScreen());
      default:
        return MaterialPageRoute(builder: (_) => const SignupScreen());
    }
  }
}

// ---------------------------------------------------------------------
// 2. AuthService
// ---------------------------------------------------------------------
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  bool get isLoggedIn => _client.auth.currentSession != null;
  User? get currentUser => _client.auth.currentUser;

  bool get isCurrentUserAdmin {
    final email = _client.auth.currentUser?.email;
    return email != null && email.toLowerCase() == kAdminEmail.toLowerCase();
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        if (phone != null) 'phone': phone,
      },
    );
    return response;
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}

// ---------------------------------------------------------------------
// 3. SupabaseService (إدارة التخزين، الصور، الإعلانات، والملف الشخصي)
// ---------------------------------------------------------------------
const String kAdminEmail = 'sameraoaad@gmail.com';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  final SupabaseClient _client = Supabase.instance.client;
  SupabaseClient get client => _client;

  bool get isAdmin {
    final email = _client.auth.currentUser?.email;
    return email != null && email.toLowerCase() == kAdminEmail.toLowerCase();
  }

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<String> compressAndUploadImage(File file, {required String adId}) async {
    final compressedFile = await _compressImage(file);
    final fileBytes = await compressedFile.readAsBytes();
    final ext = p.extension(compressedFile.path).replaceAll('.', '');
    final fileName = '$adId/${const Uuid().v4()}.$ext';

    await _client.storage.from(AppConfig.adsImagesBucket).uploadBinary(
          fileName,
          fileBytes,
          fileOptions: FileOptions(
            contentType: 'image/$ext',
            upsert: false,
          ),
        );

    final publicUrl = _client.storage.from(AppConfig.adsImagesBucket).getPublicUrl(fileName);
    return publicUrl;
  }

  Future<List<String>> uploadMultipleImages(
    List<File> files, {
    required String adId,
    void Function(int uploaded, int total)? onProgress,
  }) async {
    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      final url = await compressAndUploadImage(files[i], adId: adId);
      urls.add(url);
      onProgress?.call(i + 1, files.length);
    }
    return urls;
  }

  Future<File> _compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath = p.join(
      dir.path,
      '${const Uuid().v4()}${p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path)}',
    );

    final XFile? result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 70,
      minWidth: 1280,
      minHeight: 1280,
      format: CompressFormat.jpeg,
    );

    if (result == null) return file;
    return File(result.path);
  }

  Future<void> deleteAdImages(List<String> imageUrls) async {
    final paths = imageUrls.map((url) {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final idx = segments.indexOf(AppConfig.adsImagesBucket);
      return segments.sublist(idx + 1).join('/');
    }).toList();
    if (paths.isEmpty) return;
    await _client.storage.from(AppConfig.adsImagesBucket).remove(paths);
  }

  Future<String> createAdRecord(Map<String, dynamic> data) async {
    final response = await _client.from('ads').insert(data).select('id').single();
    return response['id'] as String;
  }

  Future<void> updateAdImages(String adId, List<String> imageUrls) async {
    await _client.from('ads').update({'image_urls': imageUrls}).eq('id', adId);
  }

  Future<Map<String, dynamic>> fetchAdById(String adId) async {
    await _client.rpc('increment_ad_views', params: {'ad_id_input': adId}).catchError((_) {});
    final response = await _client.from('ads').select().eq('id', adId).single();
    return response;
  }

  Future<List<Map<String, dynamic>>> fetchMyAds(String userId) async {
    final response = await _client
        .from('ads')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> markAsSold(String adId, {required bool sold}) async {
    await _client.from('ads').update({'is_sold': sold}).eq('id', adId);
  }

  Future<void> deleteAd(String adId, {required List<String> imageUrls}) async {
    await deleteAdImages(imageUrls);
    await _client.from('ads').delete().eq('id', adId);
  }

  Future<List<Map<String, dynamic>>> searchAds({
    String? keyword,
    String? province,
    String? categoryId,
    String? subCategoryId,
    String? condition,
    double? minPrice,
    double? maxPrice,
    int limit = 30,
    int offset = 0,
  }) async {
    var query = _client.from('ads').select().eq('is_active', true);

    if (keyword != null && keyword.trim().isNotEmpty) {
      query = query.ilike('title', '%${keyword.trim()}%');
    }
    if (province != null && province.isNotEmpty) {
      query = query.eq('province', province);
    }
    if (categoryId != null && categoryId.isNotEmpty) {
      query = query.eq('category_id', categoryId);
    }
    if (subCategoryId != null && subCategoryId.isNotEmpty) {
      query = query.eq('sub_category_id', subCategoryId);
    }
    if (condition != null && condition.isNotEmpty) {
      query = query.eq('condition', condition);
    }
    if (minPrice != null) {
      query = query.gte('price_syp', minPrice);
    }
    if (maxPrice != null) {
      query = query.lte('price_syp', maxPrice);
    }

    final response = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    return await _client.from('profiles').select().eq('id', userId).maybeSingle();
  }

  Future<void> updateProfile(String userId, Map<String, dynamic> data) async {
    await _client.from('profiles').update(data).eq('id', userId);
  }
}

// ---------------------------------------------------------------------
// 4. MarketplaceService & MonetizationChatService
// ---------------------------------------------------------------------
class MarketplaceService {
  MarketplaceService._internal();
  static final MarketplaceService instance = MarketplaceService._internal();
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchCategories() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('categories')
          .select()
          .order('sort_order', ascending: true);
      return rows;
    } on PostgrestException {
      return [];
    }
  }
}

class MonetizationChatService {
  MonetizationChatService._();
  static final MonetizationChatService instance = MonetizationChatService._();
  SupabaseClient get _client => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchConversations() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    final data = await _client
        .from('conversations')
        .select()
        .or('buyer_id.eq.$userId,seller_id.eq.$userId')
        .order('last_message_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> fetchMessages(String conversationId) async {
    final data = await _client
        .from('chat_messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> sendMessage({
    required String conversationId,
    required String content,
  }) async {
    final senderId = _client.auth.currentUser?.id;
    if (senderId == null) throw StateError('يجب تسجيل الدخول لإرسال رسالة');
    await _client.from('chat_messages').insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content,
    });
  }

  Future<void> markMessagesAsRead(String conversationId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('chat_messages')
        .update({'is_read': true})
        .eq('conversation_id', conversationId)
        .neq('sender_id', userId);
  }

  RealtimeChannel subscribeToConversationMessages({
    required String conversationId,
    required void Function(Map<String, dynamic> message) onNewMessage,
  }) {
    final channel = _client
        .channel('chat_messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            onNewMessage(payload.newRecord);
          },
        );
    channel.subscribe();
    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }
}

// ---------------------------------------------------------------------
// 5. AppTheme
// ---------------------------------------------------------------------
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: AppConfig.primaryColor,
      primary: AppConfig.primaryColor,
      secondary: AppConfig.secondaryColor,
      error: AppConfig.errorColor,
      surface: AppConfig.surfaceColor,
      brightness: Brightness.light,
    );

    final TextTheme baseTextTheme = GoogleFonts.cairoTextTheme();

    final TextTheme textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        color: AppConfig.textPrimaryColor,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        color: AppConfig.textPrimaryColor,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        color: AppConfig.textPrimaryColor,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        color: AppConfig.textPrimaryColor,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        color: AppConfig.textPrimaryColor,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        color: AppConfig.textSecondaryColor,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppConfig.backgroundColor,
      textTheme: textTheme,
      fontFamily: GoogleFonts.cairo().fontFamily,
      dividerColor: AppConfig.dividerColor,
      appBarTheme: AppBarTheme(
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppConfig.surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppConfig.dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppConfig.dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppConfig.primaryColor, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppConfig.errorColor, width: 1.2),
        ),
        labelStyle: GoogleFonts.cairo(color: AppConfig.textSecondaryColor),
        hintStyle: GoogleFonts.cairo(color: AppConfig.textSecondaryColor),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConfig.primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.cairo(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 6. Custom Widgets (CustomTextField, CustomButton)
// ---------------------------------------------------------------------
class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData prefixIcon;
  final bool obscureText;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final Widget? suffixIcon;
  final TextInputAction textInputAction;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.prefixIcon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.suffixIcon,
    this.textInputAction = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
      validator: validator,
      style: const TextStyle(color: AppConfig.textPrimaryColor),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(prefixIcon, color: AppConfig.primaryColor),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class CustomButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool outlined;
  final IconData? icon;

  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.outlined = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final Widget child = isLoading
        ? const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          );

    if (outlined) {
      return OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        child: child,
      );
    }

    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      child: child,
    );
  }
}

// ---------------------------------------------------------------------
// 7. Screens (SignupScreen & ConversationsListScreen)
// ---------------------------------------------------------------------
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await AuthService.instance.signUp(
        email: _emailController.text,
        password: _passwordController.text,
        fullName: _fullNameController.text,
        phone: _phoneController.text,
      );

      if (!mounted) return;

      final bool isAdmin = AuthService.instance.isCurrentUserAdmin;
      _showSnack(
        isAdmin
            ? 'تم إنشاء حساب المشرف بنجاح.'
            : 'تم إنشاء الحساب بنجاح، أهلاً بك في سوق سوريا الشامل.',
      );

      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
        (route) => false,
      );
    } on AuthException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (e) {
      _showSnack('حدث خطأ غير متوقع، حاول مرة أخرى.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppConfig.errorColor : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: const Text('إنشاء حساب جديد'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppConfig.appName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppConfig.primaryColor,
                      ),
                ),
                const SizedBox(height: 24),
                CustomTextField(
                  controller: _fullNameController,
                  label: 'الاسم الكامل',
                  prefixIcon: Icons.person_outline_rounded,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'يرجى إدخال الاسم الكامل';
                    }
                    if (value.trim().length < 3) {
                      return 'الاسم قصير جداً';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _emailController,
                  label: 'البريد الإلكتروني',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    final String v = value?.trim() ?? '';
                    if (v.isEmpty) {
                      return 'يرجى إدخال البريد الإلكتروني';
                    }
                    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    if (!emailRegex.hasMatch(v)) {
                      return 'صيغة البريد الإلكتروني غير صحيحة';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _phoneController,
                  label: 'رقم الهاتف (اختياري)',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final phoneRegex = RegExp(r'^[0-9+\s-]{7,15}$');
                    if (!phoneRegex.hasMatch(value.trim())) {
                      return 'رقم الهاتف غير صحيح';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _passwordController,
                  label: 'كلمة المرور',
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppConfig.textSecondaryColor,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'يرجى إدخال كلمة المرور';
                    }
                    if (value.length < 6) {
                      return 'كلمة المرور يجب ألا تقل عن 6 أحرف';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _confirmPasswordController,
                  label: 'تأكيد كلمة المرور',
                  prefixIcon: Icons.lock_reset_rounded,
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppConfig.textSecondaryColor,
                    ),
                    onPressed: () {
                      setState(() =>
                          _obscureConfirmPassword = !_obscureConfirmPassword);
                    },
                  ),
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return 'كلمتا المرور غير متطابقتين';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                CustomButton(
                  label: 'إنشاء الحساب',
                  isLoading: _isLoading,
                  onPressed: _handleSignup,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed(AppRoutes.login);
                  },
                  child: const Text('لديك حساب بالفعل؟ سجّل دخولك هنا'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ConversationsListScreen extends StatelessWidget {
  const ConversationsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الرسائل والمحادثات')),
      body: const Center(
        child: Text('مرحباً بك في لوحة تحكم سوق سوريا الشامل'),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 8. (ملاحظة) نقطة الدخول الرئيسية main() وكلاس SouqSyriaApp موجودان
// بنهاية هذا الملف تحت عنوان "13. Full App Root Entry Point"، وهي
// النسخة الوحيدة المعتمدة. تم حذف نسخة مكررة منهما كانت موجودة هنا
// سابقاً لأن Dart لا يسمح بتعريف نفس الدالة/الكلاس مرتين في نفس
// الملف (خطأ ترجمة "duplicate definition").
// ---------------------------------------------------------------------
// =====================================================================
// المشروع الكامل (الجزء الثاني): سوق سوريا الشامل (إدارة الإعلانات والشاشات)
// =====================================================================
// (ملاحظة: تم حذف استيرادات مكررة كانت هنا - dart:io، flutter/material،
// supabase_flutter - لأنها موجودة أصلاً بأعلى الملف، وDart لا يسمح
// بوجود أي "import" بعد بداية تعريف الكلاسات، فهذا خطأ ترجمة مباشر.)

// ---------------------------------------------------------------------
// 9. LoginScreen (شاشة تسجيل الدخول المتكاملة)
// ---------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await AuthService.instance.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل الدخول بنجاح')),
      );

      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
        (route) => false,
      );
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppConfig.errorColor),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ غير متوقع'), backgroundColor: AppConfig.errorColor),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(title: const Text('تسجيل الدخول')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Text(
                  'أهلاً بك مجدداً',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppConfig.primaryColor,
                      ),
                ),
                const SizedBox(height: 32),
                CustomTextField(
                  controller: _emailController,
                  label: 'البريد الإلكتروني',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (val) => val == null || val.trim().isEmpty ? 'يرجى إدخال البريد الإلكتروني' : null,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _passwordController,
                  label: 'كلمة المرور',
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (val) => val == null || val.isEmpty ? 'يرجى إدخال كلمة المرور' : null,
                ),
                const SizedBox(height: 24),
                CustomButton(
                  label: 'تسجيل الدخول',
                  isLoading: _isLoading,
                  onPressed: _handleLogin,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed(AppRoutes.signup);
                  },
                  child: const Text('ليس لديك حساب؟ إنشاء حساب جديد'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 10. Ad Details & Management Screen (شاشة تفاصيل الإعلان والتحكم به)
// ---------------------------------------------------------------------
class AdDetailScreen extends StatefulWidget {
  final String adId;
  const AdDetailScreen({super.key, required this.adId});

  @override
  State<AdDetailScreen> createState() => _AdDetailScreenState();
}

class _AdDetailScreenState extends State<AdDetailScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _adData;

  @override
  void initState() {
    super.initState();
    _loadAdDetails();
  }

  Future<void> _loadAdDetails() async {
    try {
      final data = await SupabaseService.instance.fetchAdById(widget.adId);
      if (mounted) {
        setState(() {
          _adData = data;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الإعلان')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_adData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الإعلان')),
        body: const Center(child: Text('الإعلان غير موجود أو تم حذفه.')),
      );
    }

    final ad = _adData!;
    final List images = ad['image_urls'] ?? [];
    final bool isSold = ad['is_sold'] ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(ad['title'] ?? 'تفاصيل الإعلان'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (images.isNotEmpty)
              SizedBox(
                height: 250,
                child: PageView.builder(
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    return Image.network(
                      images[index],
                      fit: BoxFit.cover,
                    );
                  },
                ),
              )
            else
              Container(
                height: 200,
                color: Colors.grey[200],
                child: const Icon(Icons.image_not_supported, size: 64, color: Colors.grey),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          ad['title'] ?? '',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      if (isSold)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppConfig.errorColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('مباع', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${ad['price_syp'] ?? 0} ليرة سورية',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppConfig.secondaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'الوصف:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ad['description'] ?? 'لا يوجد وصف متاح.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 11. Chat Room Screen (شاشة المحادثة الفورية)
// ---------------------------------------------------------------------
class ChatRoomScreen extends StatefulWidget {
  final String conversationId;
  final String peerName;

  const ChatRoomScreen({
    super.key,
    required this.conversationId,
    required this.peerName,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  RealtimeChannel? _chatChannel;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    try {
      final messages = await MonetizationChatService.instance.fetchMessages(widget.conversationId);
      await MonetizationChatService.instance.markMessagesAsRead(widget.conversationId);

      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
        });
      }

      _chatChannel = MonetizationChatService.instance.subscribeToConversationMessages(
        conversationId: widget.conversationId,
        onNewMessage: (newMessage) {
          if (mounted) {
            setState(() {
              _messages.add(newMessage);
            });
            MonetizationChatService.instance.markMessagesAsRead(widget.conversationId);
          }
        },
      );
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    if (_chatChannel != null) {
      MonetizationChatService.instance.unsubscribe(_chatChannel!);
    }
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    try {
      await MonetizationChatService.instance.sendMessage(
        conversationId: widget.conversationId,
        content: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إرسال الرسالة: $e'), backgroundColor: AppConfig.errorColor),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: Text(widget.peerName)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg['sender_id'] == currentUserId;

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isMe ? AppConfig.primaryColor : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
                            ],
                          ),
                          child: Text(
                            msg['content'] ?? '',
                            style: TextStyle(color: isMe ? Colors.white : AppConfig.textPrimaryColor),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'اكتب رسالتك...',
                            border: InputBorder.none,
                            filled: false,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: AppConfig.primaryColor),
                        onPressed: _sendMessage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
// =====================================================================
// المشروع الكامل (الجزء الثالث): سوق سوريا الشامل (الفلترة، البحث والتشغيل)
// =====================================================================
// (نفس الملاحظة: تم حذف استيرادات مكررة موجودة أصلاً بأعلى الملف)

// ---------------------------------------------------------------------
// 12. Search & Filter Screen (شاشة البحث والفلترة المتقدمة للإعلانات)
// ---------------------------------------------------------------------
class SearchAdsScreen extends StatefulWidget {
  const SearchAdsScreen({super.key});

  @override
  State<SearchAdsScreen> createState() => _SearchAdsScreenState();
}

class _SearchAdsScreenState extends State<SearchAdsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedProvince;
  String? _selectedCategory;
  double? _minPrice;
  double? _maxPrice;

  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = false;

  final List<String> _syrianProvinces = [
    'دمشق',
    'ريف دمشق',
    'حلب',
    'حمص',
    'حماة',
    'اللاذقية',
    'طرطوس',
    'إدلب',
    'دير الزور',
    'الرقة',
    'الحسكة',
    'درعا',
    'السويداء',
    'القنيطرة'
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _performSearch();
  }

  Future<void> _loadCategories() async {
    final cats = await MarketplaceService.instance.fetchCategories();
    if (mounted) {
      setState(() {
        _categories = cats;
      });
    }
  }

  Future<void> _performSearch() async {
    setState(() => _isLoading = true);
    try {
      final results = await SupabaseService.instance.searchAds(
        keyword: _searchController.text,
        province: _selectedProvince,
        categoryId: _selectedCategory,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
      );
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بحث والفلترة الشاملة')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'ابحث عن منتج أو خدمة...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _performSearch,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(50, 52)),
                  child: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          // === تمت إضافة هذا القسم لأن الشاشة كانت تجلب المحافظات
          // والأقسام وتُخزّنها بمتغيرات (_selectedProvince،
          // _selectedCategory، _categories) دون عرضها أبداً بالواجهة،
          // رغم أن عنوان الشاشة "الفلترة المتقدمة". الآن الفلترة تعمل
          // فعلياً وتستخدم كل المتغيرات المعرّفة أصلاً بالكود. ===
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedProvince,
                        decoration: const InputDecoration(labelText: 'المحافظة'),
                        items: _syrianProvinces
                            .map((province) => DropdownMenuItem(value: province, child: Text(province)))
                            .toList(),
                        onChanged: (value) {
                          setState(() => _selectedProvince = value);
                          _performSearch();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        decoration: const InputDecoration(labelText: 'القسم'),
                        items: _categories
                            .map((cat) => DropdownMenuItem(
                                  value: cat['id']?.toString(),
                                  child: Text(cat['name']?.toString() ?? ''),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() => _selectedCategory = value);
                          _performSearch();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'أقل سعر'),
                        onChanged: (value) => _minPrice = double.tryParse(value),
                        onSubmitted: (_) => _performSearch(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'أعلى سعر'),
                        onChanged: (value) => _maxPrice = double.tryParse(value),
                        onSubmitted: (_) => _performSearch(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'تطبيق نطاق السعر',
                      onPressed: _performSearch,
                      icon: const Icon(Icons.filter_alt, color: AppConfig.primaryColor),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? const Center(child: Text('لا توجد نتائج مطابقة لبحثك'))
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final ad = _searchResults[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              title: Text(ad['title'] ?? ''),
                              subtitle: Text('${ad['price_syp'] ?? 0} ليرة سورية - ${ad['province'] ?? ''}'),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AdDetailScreen(adId: ad['id']),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// 13. Full App Root Entry Point (main.dart النهائي المكتمل)
// ---------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const SouqSyriaApp());
}

class SouqSyriaApp extends StatelessWidget {
  const SouqSyriaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isLoggedIn = AuthService.instance.isLoggedIn;

    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      initialRoute: isLoggedIn ? AppRoutes.home : AppRoutes.signup,
      onGenerateRoute: AppRoutes.generateRoute,
    );
  }
}