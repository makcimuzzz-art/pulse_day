import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const String serverBaseUrl = 'http://201.24.53.232:8000';
const String dailyUrl = '$serverBaseUrl/api/daily';
const String editorialUrl = '$serverBaseUrl/api/editorial';
const String yaraUrl = 'http://201.24.53.232:8001/api/yara/chat';
const String yaraAvatarUrl = '$serverBaseUrl/static/yara.png';
const String firebaseDatabaseUrl =
    'https://pulse-day-default-rtdb.firebaseio.com';
const String userKey = 'user_default';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const PulseApp());
}

class PulseApp extends StatelessWidget {
  const PulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ДИС.Новости',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2457A6)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF17243A),
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _setupNotifications();
    _openNextScreen();
  }

  Future<void> _setupNotifications() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        final token = await messaging.getToken();

        if (token != null) {
          await http.put(
            Uri.parse('$firebaseDatabaseUrl/tokens/$token.json'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'active': true,
              'created': DateTime.now().toIso8601String(),
            }),
          );
        }

        FirebaseMessaging.onMessage.listen((message) {
          debugPrint('Получено уведомление: ${message.notification?.title}');
        });
      }
    } catch (e) {
      debugPrint('Не удалось настроить уведомления: $e');
    }
  }

  Future<void> _openNextScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final categories = prefs.getStringList('selected_categories') ?? [];

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => categories.isNotEmpty
            ? const MainScreen()
            : const CategorySelectionScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class CategorySelectionScreen extends StatefulWidget {
  const CategorySelectionScreen({super.key});

  @override
  State<CategorySelectionScreen> createState() =>
      _CategorySelectionScreenState();
}

class _CategorySelectionScreenState extends State<CategorySelectionScreen> {
  final Set<String> selected = {};

  final List<String> categories = const [
    'Политика',
    'Экономика',
    'Технологии',
    'Здоровье',
    'Спорт',
    'Культура',
    'Общество',
    'Происшествия',
  ];

  Future<void> _save() async {
    if (selected.length < 3) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('selected_categories', selected.toList());

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ДИС.Новости')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 12),
              const Icon(
                Icons.newspaper_rounded,
                size: 48,
                color: Color(0xFF2457A6),
              ),
              const SizedBox(height: 16),
              const Text(
                'Добро пожаловать в ДИС.Новости',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Выберите не менее трёх тем, чтобы сформировать персональную ленту.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  children: categories.map((category) {
                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      child: CheckboxListTile(
                        value: selected.contains(category),
                        title: Text(category),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              selected.add(category);
                            } else {
                              selected.remove(category);
                            }
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selected.length >= 3 ? _save : null,
                  child: Text('Продолжить (${selected.length}/3)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  Map<String, dynamic>? dailyData;

  List<Map<String, dynamic>> allNews = [];
  List<Map<String, dynamic>> digestNews = [];
  List<Map<String, dynamic>> topNews = [];

  List<String> userCategories = [];
  Map<String, String> reactions = {};

  bool loading = true;
  bool digestExpanded = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    userCategories = prefs.getStringList('selected_categories') ?? [];

    await _loadReactions();
    await _fetchData();
  }

  Future<void> _loadReactions() async {
    try {
      final response = await http
          .get(Uri.parse('$firebaseDatabaseUrl/reactions/$userKey.json'))
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200 && response.body != 'null') {
        final decoded = jsonDecode(response.body);

        if (decoded is Map) {
          reactions = decoded.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          );
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки реакций: $e');
    }
  }

  String _newsKey(Map<String, dynamic> item) {
    final id = item['id']?.toString();

    if (id != null && id.isNotEmpty) return id;

    final link = item['link']?.toString() ?? '';

    if (link.isNotEmpty) {
      return Uri.encodeComponent(link).replaceAll('.', '_');
    }

    return Uri.encodeComponent(item['title']?.toString() ?? 'news');
  }

  Future<void> _saveReaction(
    Map<String, dynamic> item,
    String reaction,
  ) async {
    final key = _newsKey(item);
    final oldValue = reactions[key];

    setState(() {
      if (oldValue == reaction) {
        reactions.remove(key);
      } else {
        reactions[key] = reaction;
      }
    });

    try {
      final uri =
          Uri.parse('$firebaseDatabaseUrl/reactions/$userKey/$key.json');

      final response = oldValue == reaction
          ? await http.delete(uri).timeout(const Duration(seconds: 10))
          : await http
              .put(
                uri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(reaction),
              )
              .timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        if (oldValue == reaction) {
          reactions[key] = reaction;
        } else {
          reactions.remove(key);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить реакцию')),
      );

      debugPrint('Ошибка сохранения реакции: $e');
    }
  }

  double _timestamp(Map<String, dynamic> item) {
    final value = item['timestamp'];

    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;

    return 0;
  }

  String _normalizeTitle(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^а-яa-z0-9 ]', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<Map<String, dynamic>> _deduplicateNews(
    List<Map<String, dynamic>> news,
  ) {
    final result = <Map<String, dynamic>>[];
    final seenLinks = <String>{};
    final seenTitles = <String>{};

    for (final item in news) {
      final link = (item['link'] ?? '').toString().trim().toLowerCase();
      final title = _normalizeTitle(
        (item['title'] ?? '').toString(),
      );

      if (link.isNotEmpty && !seenLinks.add(link)) continue;
      if (title.isNotEmpty && !seenTitles.add(title)) continue;

      result.add(item);
    }

    return result;
  }

  List<Map<String, dynamic>> _diversifyNews(
    List<Map<String, dynamic>> news,
  ) {
    final sorted = [...news]
      ..sort((a, b) => _timestamp(b).compareTo(_timestamp(a)));

    final buckets = <String, List<Map<String, dynamic>>>{};

    for (final item in sorted) {
      final category = (item['category'] ?? 'Другое').toString();
      final scope = (item['scope'] ?? '').toString().toLowerCase();
      final region = (item['region'] ?? '').toString().trim();

      final geography = scope == 'federal'
          ? 'Федеральные'
          : region.isNotEmpty
              ? 'Региональные'
              : 'Другие';

      final bucket = '$category|$geography';
      buckets.putIfAbsent(bucket, () => []).add(item);
    }

    final keys = buckets.keys.toList();
    final result = <Map<String, dynamic>>[];

    while (buckets.values.any((items) => items.isNotEmpty)) {
      for (final key in keys) {
        final items = buckets[key]!;

        if (items.isNotEmpty) {
          result.add(items.removeAt(0));
        }
      }
    }

    return result;
  }

  Future<void> _fetchData() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }

    try {
      final response = await http
          .get(Uri.parse(dailyUrl))
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        throw Exception('Сервер вернул код ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Неверный формат ответа сервера');
      }

      final rawNews = decoded['news'];

      final receivedNews = rawNews is List
          ? rawNews
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where(
                (item) =>
                    (item['title'] ?? '').toString().trim().isNotEmpty,
              )
              .toList()
          : <Map<String, dynamic>>[];

      final uniqueNews = _deduplicateNews(receivedNews);
      final news = _diversifyNews(uniqueNews);

      // Персональный дайджест: только выбранные пользователем категории.
      // Если материалов мало, не заполняем его случайными новостями.
      final digest = <Map<String, dynamic>>[];
      final usedDigestIds = <String>{};

      for (final category in userCategories) {
        final match = news.cast<Map<String, dynamic>?>().firstWhere(
              (item) =>
                  item != null &&
                  item['category']?.toString().toLowerCase() ==
                      category.toLowerCase(),
              orElse: () => null,
            );

        if (match != null) {
          final key = _newsKey(match);

          if (usedDigestIds.add(key)) {
            digest.add(match);
          }
        }
      }

      // Главные события — свежие материалы разных категорий.
      final sortedNews = [...news]
        ..sort((a, b) => _timestamp(b).compareTo(_timestamp(a)));

      final picked = <Map<String, dynamic>>[];
      final usedKeys = <String>{};
      final usedCategories = <String>{};

      for (final item in sortedNews) {
        final category = (item['category'] ?? 'Другое').toString();

        if (usedCategories.add(category) &&
            usedKeys.add(_newsKey(item))) {
          picked.add(item);
        }

        if (picked.length == 5) break;
      }

      if (picked.length < 5) {
        for (final item in sortedNews) {
          if (usedKeys.add(_newsKey(item))) {
            picked.add(item);
          }

          if (picked.length == 5) break;
        }
      }

      if (!mounted) return;

      setState(() {
        dailyData = decoded;
        allNews = news;
        digestNews = digest;
        topNews = picked;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error =
            'Не удалось загрузить новости. Проверьте подключение и попробуйте ещё раз.';
        loading = false;
      });

      debugPrint('Ошибка загрузки ленты: $e');
    }
  }

  void _openYara() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const YaraScreen(),
    );
  }

  Future<void> _openNews(Map<String, dynamic> item) async {
    final link = item['link']?.toString() ?? '';
    final uri = Uri.tryParse(link);

    if (uri == null || !uri.hasScheme) return;

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _shareNews(Map<String, dynamic> item) async {
    final title = item['title']?.toString() ?? 'Новость';
    final link = item['link']?.toString() ?? '';

    await Share.share('$title\n\nЧитать: $link\n\n— ДИС.Новости');
  }
    @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ДИС.Новости',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить новости',
            onPressed: loading ? null : _fetchData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _ErrorView(message: error!, onRetry: _fetchData)
              : RefreshIndicator(
                  onRefresh: _fetchData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _WeatherCard(
                        weather: _asMap(dailyData?['weather']),
                      ),
                      const SizedBox(height: 20),
                      _DigestPanel(
                        news: digestNews,
                        expanded: digestExpanded,
                        onToggle: () {
                          setState(() {
                            digestExpanded = !digestExpanded;
                          });
                        },
                        reactions: reactions,
                        newsKey: _newsKey,
                        onReact: _saveReaction,
                        onOpen: _openNews,
                        onShare: _shareNews,
                      ),
                      const SizedBox(height: 22),
                      _sectionHeading(
                        'Что сегодня произошло важного?',
                        subtitle: 'Главные события дня из разных сфер',
                      ),
                      const SizedBox(height: 10),
                      if (topNews.isEmpty)
                        const _EmptyPanel(
                          text: 'Пока нет подходящих главных событий.',
                        )
                      else
                        ...topNews.map(
                          (item) => _NewsCard(
                            item: item,
                            reaction: reactions[_newsKey(item)],
                            onReact: (value) => _saveReaction(item, value),
                            onOpen: () => _openNews(item),
                            onShare: () => _shareNews(item),
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openYara,
        backgroundColor: const Color(0xFF6844A5),
        elevation: 5,
        tooltip: 'Спросить Яру',
        child: ClipOval(
          child: Image.network(
            yaraAvatarUrl,
            width: 54,
            height: 54,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 27,
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.newspaper_outlined),
            label: 'Новости',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt),
            label: 'Блоги',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note),
            label: 'Редакция',
          ),
        ],
        onDestinationSelected: (index) {
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NewsListScreen(
                  news: allNews,
                  reactions: reactions,
                  newsKey: _newsKey,
                  onReact: _saveReaction,
                  onOpen: _openNews,
                  onShare: _shareNews,
                ),
              ),
            ).then((_) {
              if (mounted) setState(() {});
            });
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const BlogsScreen(),
              ),
            );
          } else if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const EditorialScreen(),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _sectionHeading(
    String title, {
    String? subtitle,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  return <String, dynamic>{};
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  final Map<String, dynamic> weather;

  const _WeatherCard({
    required this.weather,
  });

  @override
  Widget build(BuildContext context) {
    final condition =
        (weather['condition'] ?? 'Погода не указана').toString();

    final temp = weather['temp'] ?? weather['temperature'] ?? '--';

    IconData icon = Icons.wb_cloudy_outlined;
    final lower = condition.toLowerCase();

    if (lower.contains('солн') || lower.contains('ясно')) {
      icon = Icons.wb_sunny_outlined;
    } else if (lower.contains('дожд') || lower.contains('лив')) {
      icon = Icons.grain;
    } else if (lower.contains('снег')) {
      icon = Icons.ac_unit;
    } else if (lower.contains('гроз')) {
      icon = Icons.thunderstorm;
    } else if (lower.contains('туман')) {
      icon = Icons.foggy;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2457A6),
            Color(0xFF4388C9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: Colors.white,
            size: 42,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$temp°C',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  condition,
                  style: const TextStyle(color: Colors.white70),
                ),
                if (weather['city'] != null)
                  Text(
                    weather['city'].toString(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(
            Icons.location_on_outlined,
            color: Colors.white70,
          ),
        ],
      ),
    );
  }
}

class _DigestPanel extends StatelessWidget {
  final List<Map<String, dynamic>> news;
  final bool expanded;
  final VoidCallback onToggle;
  final Map<String, String> reactions;
  final String Function(Map<String, dynamic>) newsKey;
  final Future<void> Function(Map<String, dynamic>, String) onReact;
  final Future<void> Function(Map<String, dynamic>) onOpen;
  final Future<void> Function(Map<String, dynamic>) onShare;

  const _DigestPanel({
    required this.news,
    required this.expanded,
    required this.onToggle,
    required this.reactions,
    required this.newsKey,
    required this.onReact,
    required this.onOpen,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onToggle,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF243F78),
                Color(0xFF5C55A5),
                Color(0xFF8064B8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF51458F).withOpacity(0.20),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.17),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 27,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ваш персональный дайджест',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Подобрано по вашим интересам · ${news.length} новостей',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.arrow_forward_ios,
                      color: Colors.white,
                      size: expanded ? 25 : 17,
                    ),
                  ],
                ),
              ),
              if (expanded)
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(24),
                    ),
                  ),
                  child: news.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(17),
                          child: Text(
                            'Пока нет новостей по выбранным категориям. Загляните позже — подборка обновится.',
                            style: TextStyle(
                              color: Colors.black54,
                              height: 1.4,
                            ),
                          ),
                        )
                      : Column(
                          children: news
                              .map(
                                (item) => _CompactNewsTile(
                                  item: item,
                                  reaction: reactions[newsKey(item)],
                                  onReact: (value) => onReact(item, value),
                                  onOpen: () => onOpen(item),
                                  onShare: () => onShare(item),
                                ),
                              )
                              .toList(),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}class _CompactNewsTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final String? reaction;
  final ValueChanged<String> onReact;
  final VoidCallback onOpen;
  final VoidCallback onShare;

  const _CompactNewsTile({
    required this.item,
    required this.reaction,
    required this.onReact,
    required this.onOpen,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MetadataLine(item: item),
            if (_newsImageUrl(item).isNotEmpty) ...[
              const SizedBox(height: 9),
              _NewsMedia(item: item),
            ],
            const SizedBox(height: 5),
            Text(
              item['title']?.toString() ?? 'Без названия',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                height: 1.3,
              ),
            ),
            if ((item['description'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                item['description'].toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
            _ReactionRow(
              reaction: reaction,
              onReact: onReact,
              onShare: onShare,
              onOpen: onOpen,
            ),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}

String _newsImageUrl(Map<String, dynamic> item) {
  for (final key in [
    'image_url',
    'image',
    'photo',
    'thumbnail',
  ]) {
    final value = item[key]?.toString().trim() ?? '';

    if (value.startsWith('https://') || value.startsWith('http://')) {
      return value;
    }
  }

  return '';
}

String _newsVideoUrl(Map<String, dynamic> item) {
  for (final key in [
    'video_url',
    'video',
    'media_url',
  ]) {
    final value = item[key]?.toString().trim() ?? '';

    if (value.startsWith('https://') || value.startsWith('http://')) {
      return value;
    }
  }

  return '';
}

class _NewsMedia extends StatelessWidget {
  final Map<String, dynamic> item;

  const _NewsMedia({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = _newsImageUrl(item);
    final videoUrl = _newsVideoUrl(item);

    if (imageUrl.isEmpty && videoUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              width: double.infinity,
              height: 190,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return Container(
                  height: 130,
                  width: double.infinity,
                  color: const Color(0xFFE9EDF4),
                  child: const Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.black38,
                    size: 34,
                  ),
                );
              },
            )
          else
            Container(
              height: 150,
              width: double.infinity,
              color: const Color(0xFF202B45),
              child: const Icon(
                Icons.play_circle_outline,
                color: Colors.white70,
                size: 52,
              ),
            ),
          if (videoUrl.isNotEmpty)
            Positioned(
              right: 10,
              bottom: 10,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.72),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final uri = Uri.tryParse(videoUrl);

                  if (uri != null) {
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Смотреть видео'),
              ),
            ),
        ],
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String? reaction;
  final ValueChanged<String> onReact;
  final VoidCallback onOpen;
  final VoidCallback onShare;

  const _NewsCard({
    required this.item,
    required this.reaction,
    required this.onReact,
    required this.onOpen,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MetadataLine(item: item),
              const SizedBox(height: 9),
              _NewsMedia(item: item),
              if (_newsImageUrl(item).isNotEmpty ||
                  _newsVideoUrl(item).isNotEmpty)
                const SizedBox(height: 8),
              Text(
                item['title']?.toString() ?? 'Без названия',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if ((item['description'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  item['description'].toString(),
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              _ReactionRow(
                reaction: reaction,
                onReact: onReact,
                onShare: onShare,
                onOpen: onOpen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataLine extends StatelessWidget {
  final Map<String, dynamic> item;

  const _MetadataLine({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final category = (item['category'] ?? 'Новости').toString();
    final source = (item['source'] ?? '').toString();
    final region = (item['region'] ?? '').toString();
    final scope = (item['scope'] ?? '').toString();

    final label = scope == 'federal'
        ? 'Федеральная'
        : region.isNotEmpty
            ? region
            : 'Новости';

    return Wrap(
      spacing: 7,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _SmallTag(
          text: category,
          color: const Color(0xFFEAF0FC),
        ),
        _SmallTag(
          text: label,
          color: const Color(0xFFF0F2F5),
        ),
        if (source.isNotEmpty)
          Text(
            source,
            style: const TextStyle(
              color: Colors.black45,
              fontSize: 10,
            ),
          ),
        if (item['timestamp'] != null)
          Text(
            _formatTimestamp(item['timestamp']),
            style: const TextStyle(
              color: Colors.black45,
              fontSize: 10,
            ),
          ),
      ],
    );
  }
}

class _SmallTag extends StatelessWidget {
  final String text;
  final Color color;

  const _SmallTag({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _formatTimestamp(dynamic raw) {
  DateTime? date;

  if (raw is num) {
    date = DateTime.fromMillisecondsSinceEpoch(
      raw.toInt() * 1000,
    );
  } else if (raw is String) {
    date = DateTime.tryParse(raw);

    final numeric = double.tryParse(raw);

    if (date == null && numeric != null) {
      date = DateTime.fromMillisecondsSinceEpoch(
        numeric.toInt() * 1000,
      );
    }
  }

  if (date == null) return '';

  final local = date.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');

  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')} $hh:$mm';
}

class _ReactionRow extends StatelessWidget {
  final String? reaction;
  final ValueChanged<String> onReact;
  final VoidCallback onShare;
  final VoidCallback onOpen;

  const _ReactionRow({
    required this.reaction,
    required this.onReact,
    required this.onShare,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Нравится',
          onPressed: () => onReact('like'),
          icon: Icon(
            reaction == 'like'
                ? Icons.thumb_up
                : Icons.thumb_up_outlined,
            size: 19,
            color: reaction == 'like' ? Colors.indigo : Colors.grey,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Не нравится',
          onPressed: () => onReact('dislike'),
          icon: Icon(
            reaction == 'dislike'
                ? Icons.thumb_down
                : Icons.thumb_down_outlined,
            size: 19,
            color: reaction == 'dislike' ? Colors.indigo : Colors.grey,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: onShare,
          icon: const Icon(Icons.share_outlined, size: 17),
          label: const Text('Поделиться'),
        ),
        TextButton(
          onPressed: onOpen,
          child: const Text('Читать'),
        ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final String text;

  const _EmptyPanel({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black54,
          height: 1.4,
        ),
      ),
    );
  }
}

class _YaraInvite extends StatelessWidget {
  final VoidCallback onTap;

  const _YaraInvite({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFF0EAF8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: Colors.white,
          child: Image.network(
            yaraAvatarUrl,
            width: 34,
            height: 34,
            errorBuilder: (_, __, ___) {
              return const Icon(
                Icons.auto_awesome,
                color: Colors.deepPurple,
              );
            },
          ),
        ),
        title: const Text(
          'Есть вопрос? Спросите Яру',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Новости, погода и ответы на ваши вопросы',
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
        ),
      ),
    );
  }
}
class NewsListScreen extends StatefulWidget {
  final List<Map<String, dynamic>> news;
  final Map<String, String> reactions;
  final String Function(Map<String, dynamic>) newsKey;
  final Future<void> Function(Map<String, dynamic>, String) onReact;
  final Future<void> Function(Map<String, dynamic>) onOpen;
  final Future<void> Function(Map<String, dynamic>) onShare;

  const NewsListScreen({
    super.key,
    required this.news,
    required this.reactions,
    required this.newsKey,
    required this.onReact,
    required this.onOpen,
    required this.onShare,
  });

  @override
  State<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends State<NewsListScreen> {
  String selectedCategory = 'Все';

  @override
  Widget build(BuildContext context) {
    final categories = <String>{
      'Все',
      ...widget.news.map(
        (item) => (item['category'] ?? 'Другое').toString(),
      ),
    }.toList();

    final filtered = selectedCategory == 'Все'
        ? widget.news
        : widget.news
            .where(
              (item) => item['category'] == selectedCategory,
            )
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Все новости'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 54,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final category = categories[index];

                return ChoiceChip(
                  label: Text(category),
                  selected: selectedCategory == category,
                  onSelected: (_) {
                    setState(() {
                      selectedCategory = category;
                    });
                  },
                );
              },
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('В этой категории пока нет новостей'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];

                      return _NewsCard(
                        item: item,
                        reaction: widget.reactions[widget.newsKey(item)],
                        onReact: (value) => widget.onReact(item, value),
                        onOpen: () => widget.onOpen(item),
                        onShare: () => widget.onShare(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}


// ===================== БЛОГИ ДИС =====================
// На этом первом этапе публикации хранятся только на устройстве.
// Публичная синхронизация будет включена после подключения Firebase Auth
// и настройки правил Realtime Database.
class BlogsScreen extends StatefulWidget {
  const BlogsScreen({super.key});

  @override
  State<BlogsScreen> createState() => _BlogsScreenState();
}

class _BlogsScreenState extends State<BlogsScreen> {
  static const String _storageKey = 'dis_local_blog_posts_v1';
  final TextEditingController _nameController = TextEditingController();
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _subscriptionsOnly = false;
  String _displayName = 'Автор ДИС';
  final Set<String> _likedPosts = {};
  final Set<String> _followedAuthors = {};

  @override
  void initState() {
    super.initState();
    _loadLocalData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    final savedName = prefs.getString('dis_blog_display_name');
    List<Map<String, dynamic>> loaded = [];
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          loaded = decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (e) {
        debugPrint('Не удалось прочитать локальные записи блога: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _posts = loaded;
      if (savedName != null && savedName.trim().isNotEmpty) _displayName = savedName;
      _loading = false;
    });
  }

  Future<void> _persistPosts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_posts));
  }

  Future<void> _createPost() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Новая запись', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Расскажите, что думаете или чем хотите поделиться.', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    hintText: 'Текст вашей записи…',
                    filled: true,
                    fillColor: const Color(0xFFF4F6FA),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Напишите хотя бы несколько слов' : null,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      if (formKey.currentState!.validate()) Navigator.pop(sheetContext, controller.text.trim());
                    },
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Сохранить запись'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty || !mounted) return;
    final post = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'author': _displayName,
      'text': text,
      'created_at': DateTime.now().toIso8601String(),
      'likes': 0,
    };
    setState(() => _posts.insert(0, post));
    await _persistPosts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Запись сохранена на этом устройстве')),
    );
  }

  Future<void> _editProfile() async {
    _nameController.text = _displayName;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Имя в блоге'),
        content: TextField(
          controller: _nameController,
          maxLength: 40,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Как вас будут видеть читатели'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, _nameController.text.trim()), child: const Text('Сохранить')),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dis_blog_display_name', value);
    if (mounted) setState(() => _displayName = value);
  }

  String _timeLabel(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return 'Недавно';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин. назад';
    if (diff.inDays < 1) return '${diff.inHours} ч. назад';
    if (diff.inDays < 7) return '${diff.inDays} дн. назад';
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final visiblePosts = _subscriptionsOnly
        ? _posts.where((post) => _followedAuthors.contains(post['author']?.toString())).toList()
        : _posts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Блоги ДИС', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(tooltip: 'Мой профиль', onPressed: _editProfile, icon: const Icon(Icons.account_circle_outlined)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createPost,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('Написать'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF263F79), Color(0xFF6655A5)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.forum_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 13),
                      const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Голоса читателей', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                          SizedBox(height: 4),
                          Text('Мнения, наблюдения и личные истории', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ]),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(child: _BlogFeedTab(label: 'Популярное', selected: !_subscriptionsOnly, onTap: () => setState(() => _subscriptionsOnly = false))),
                    const SizedBox(width: 8),
                    Expanded(child: _BlogFeedTab(label: 'Подписки', selected: _subscriptionsOnly, onTap: () => setState(() => _subscriptionsOnly = true))),
                  ]),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 12, 18, 8),
                  child: Row(children: [Icon(Icons.info_outline, size: 15, color: Color(0xFF64748B)), SizedBox(width: 6), Expanded(child: Text('Пока это личный режим: записи видны только на вашем устройстве.', style: TextStyle(color: Color(0xFF64748B), fontSize: 11))) ]),
                ),
                Expanded(
                  child: visiblePosts.isEmpty
                      ? _BlogEmptyState(onCreate: _createPost, subscriptionsOnly: _subscriptionsOnly)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                          itemCount: visiblePosts.length,
                          itemBuilder: (context, index) {
                            final post = visiblePosts[index];
                            final id = post['id'].toString();
                            final liked = _likedPosts.contains(id);
                            return _BlogPostCard(
                              post: post,
                              timeLabel: _timeLabel(post['created_at']),
                              liked: liked,
                              onLike: () => setState(() => liked ? _likedPosts.remove(id) : _likedPosts.add(id)),
                              onFollow: () => setState(() {
                                final author = post['author']?.toString() ?? '';
                                if (_followedAuthors.contains(author)) { _followedAuthors.remove(author); } else { _followedAuthors.add(author); }
                              }),
                              following: _followedAuthors.contains(post['author']?.toString()),
                              isOwn: post['author'] == _displayName,
                              onDelete: () async {
                                setState(() => _posts.removeWhere((item) => item['id'].toString() == id));
                                await _persistPosts();
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _BlogFeedTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _BlogFeedTab({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(14), onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: selected ? const Color(0xFF2457A6) : Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? const Color(0xFF2457A6) : const Color(0xFFE2E8F0))),
      child: Center(child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: selected ? Colors.white : const Color(0xFF475569)))),
    ),
  );
}

class _BlogEmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  final bool subscriptionsOnly;
  const _BlogEmptyState({required this.onCreate, required this.subscriptionsOnly});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 76, height: 76, decoration: BoxDecoration(color: const Color(0xFFE8EEFA), borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.edit_note_rounded, size: 38, color: Color(0xFF2457A6))),
        const SizedBox(height: 16),
        Text(subscriptionsOnly ? 'Вы пока ни на кого не подписаны' : 'Здесь начинается ваш блог', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(subscriptionsOnly ? 'Когда появятся авторы и подписки, их записи будут собраны здесь.' : 'Создайте первую запись — поделитесь мыслью, наблюдением или историей.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, height: 1.4)),
        if (!subscriptionsOnly) ...[const SizedBox(height: 18), FilledButton.icon(onPressed: onCreate, icon: const Icon(Icons.add), label: const Text('Создать запись'))],
      ]),
    ),
  );
}

class _BlogPostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final String timeLabel;
  final bool liked;
  final bool following;
  final bool isOwn;
  final VoidCallback onLike;
  final VoidCallback onFollow;
  final VoidCallback onDelete;
  const _BlogPostCard({required this.post, required this.timeLabel, required this.liked, required this.following, required this.isOwn, required this.onLike, required this.onFollow, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    final author = post['author']?.toString() ?? 'Автор';
    return Card(
      color: Colors.white, elevation: 0, margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE9EDF4))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: const Color(0xFFE8EEFA), child: Text(author.isNotEmpty ? author[0].toUpperCase() : 'А', style: const TextStyle(color: Color(0xFF2457A6), fontWeight: FontWeight.bold))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(author, style: const TextStyle(fontWeight: FontWeight.bold)), Text(timeLabel, style: const TextStyle(color: Colors.black45, fontSize: 11))])),
            if (!isOwn) TextButton(onPressed: onFollow, child: Text(following ? 'Вы подписаны' : 'Подписаться', style: const TextStyle(fontSize: 11))),
            if (isOwn) PopupMenuButton<String>(onSelected: (value) { if (value == 'delete') onDelete(); }, itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Удалить запись'))]),
          ]),
          const SizedBox(height: 14),
          Text(post['text']?.toString() ?? '', style: const TextStyle(fontSize: 15, height: 1.45, color: Color(0xFF243044))),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Row(children: [
            IconButton(onPressed: onLike, visualDensity: VisualDensity.compact, icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? const Color(0xFFE05272) : Colors.blueGrey)),
            Text('${(post['likes'] is num ? post['likes'] as num : 0) + (liked ? 1 : 0)}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(width: 14),
            const Icon(Icons.mode_comment_outlined, size: 19, color: Colors.blueGrey),
            const SizedBox(width: 5),
            const Text('Комментарии появятся позже', style: TextStyle(color: Colors.black45, fontSize: 11)),
          ]),
        ]),
      ),
    );
  }
}

class EditorialScreen extends StatefulWidget {
  const EditorialScreen({super.key});

  @override
  State<EditorialScreen> createState() => _EditorialScreenState();
}

class _EditorialScreenState extends State<EditorialScreen> {
  List<Map<String, dynamic>> articles = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _fetchEditorial();
  }

  Future<void> _fetchEditorial() async {
    try {
      final response = await http
          .get(Uri.parse(editorialUrl))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final raw = decoded is Map ? decoded['articles'] : null;

      articles = raw is List
          ? raw
              .whereType<Map>()
              .map(
                (item) => Map<String, dynamic>.from(item),
              )
              .toList()
          : [];

      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Не удалось загрузить материалы редакции.';
          loading = false;
        });
      }

      debugPrint('Ошибка редакции: $e');
    }
  }

  void _showArticle(Map<String, dynamic> article) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(22),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.all(22),
            children: [
              Text(
                article['title']?.toString() ?? 'Статья',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${article['author'] ?? 'Редакция ДИС'} • ${article['date'] ?? ''}',
                style: const TextStyle(color: Colors.black54),
              ),
              const Divider(height: 28),
              Text(
                article['full_text']?.toString() ??
                    article['text']?.toString() ??
                    'Текст пока не опубликован.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редакция ДИС'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : articles.isEmpty
                  ? const Center(
                      child: Text('Редакционных материалов пока нет'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: articles.length,
                      itemBuilder: (context, index) {
                        final article = articles[index];

                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(14),
                            title: Text(
                              article['title']?.toString() ?? 'Без названия',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                article['short_description']?.toString() ??
                                    '',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _showArticle(article),
                          ),
                        );
                      },
                    ),
    );
  }
}

class YaraScreen extends StatefulWidget {
  const YaraScreen({super.key});

  @override
  State<YaraScreen> createState() => _YaraScreenState();
}

class _YaraScreenState extends State<YaraScreen> {
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();

  final List<Map<String, String>> messages = [
    {
      'role': 'bot',
      'text':
          'Привет! Я Яра — новостная помощница ДИС. Задай вопрос о новостях или попроси помочь разобраться в теме.',
    }
  ];

  bool sending = false;

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = controller.text.trim();

    if (question.isEmpty || sending) return;

    setState(() {
      messages.add({
        'role': 'user',
        'text': question,
      });

      sending = true;
      controller.clear();
    });

    _scrollToBottom();

    try {
      final response = await http
          .post(
            Uri.parse(yaraUrl),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'user_id': userKey,
              'message': question,
            }),
          )
          .timeout(const Duration(seconds: 130));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);

      final answer = decoded is Map
          ? (decoded['answer'] ??
                  decoded['response'] ??
                  'Я не получила ответ.')
              .toString()
          : 'Сервер вернул неожиданный ответ.';

      if (!mounted) return;

      setState(() {
        messages.add({
          'role': 'bot',
          'text': answer,
        });

        sending = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        messages.add({
          'role': 'bot',
          'text':
              'Не удалось получить ответ. Попробуй ещё раз чуть позже.',
        });

        sending = false;
      });

      debugPrint('Ошибка запроса к Яре: $e');
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    Timer(const Duration(milliseconds: 120), () {
      if (mounted && scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, sheetController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF5C2790),
                    Color(0xFF8E50B8),
                  ],
                ),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Image.network(
                      yaraAvatarUrl,
                      width: 34,
                      height: 34,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return const Icon(
                          Icons.auto_awesome,
                          color: Colors.deepPurple,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Яра',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Новостная помощница ДИС',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(14),
                itemCount: messages.length + (sending ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == messages.length) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text('Яра готовит ответ...'),
                        ],
                      ),
                    );
                  }

                  final message = messages[index];
                  final isUser = message['role'] == 'user';

                  return Align(
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78,
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: isUser
                            ? const Color(0xFF62409A)
                            : const Color(0xFFF0F1F5),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Text(
                        message['text'] ?? '',
                        style: TextStyle(
                          color: isUser ? Colors.white : Colors.black87,
                          height: 1.4,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Напишите вопрос...',
                          filled: true,
                          fillColor: const Color(0xFFF3F4F7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: const Color(0xFF6844A5),
                      child: IconButton(
                        onPressed: sending ? null : _send,
                        icon: const Icon(
                          Icons.send,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}