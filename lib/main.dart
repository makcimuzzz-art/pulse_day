import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(PulseApp());
}

class PulseApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ДИС.Новости',
      theme: ThemeData(primarySwatch: Colors.blue, brightness: Brightness.light),
      home: SplashScreen(),
    );
  }
}

// ============= SPLASH SCREEN =============
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _setupNotifications();
    _checkPrefs();
  }

  Future<void> _setupNotifications() async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
        alert: true, badge: true, sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? token = await messaging.getToken();
        if (token != null) {
          await _saveTokenToFirebase(token);
        }
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          print('Получено уведомление: ${message.notification?.title}');
        });
      }
    } catch (e) {
      print('Ошибка настройки уведомлений: $e');
    }
  }

  Future<void> _saveTokenToFirebase(String token) async {
    try {
      final url = Uri.parse('https://pulse-day-default-rtdb.firebaseio.com/tokens/$token.json');
      await http.put(url, body: json.encode({
        "active": true,
        "created": DateTime.now().toIso8601String()
      }));
      print('Токен сохранён в Firebase');
    } catch (e) {
      print('Ошибка сохранения токена: $e');
    }
  }

  Future<void> _checkPrefs() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedCategories = prefs.getStringList('selected_categories');

    if (savedCategories != null && savedCategories.isNotEmpty) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainScreen()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CategorySelectionScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// ============= ЭКРАН ВЫБОРА КАТЕГОРИЙ =============
class CategorySelectionScreen extends StatefulWidget {
  @override
  _CategorySelectionScreenState createState() => _CategorySelectionScreenState();
}

class _CategorySelectionScreenState extends State<CategorySelectionScreen> {
  final Set<String> _selectedCategories = {};
  final List<String> _categories = [
    'Политика', 'Экономика', 'Технологии', 'Здоровье',
    'Спорт', 'Культура', 'Общество', 'Происшествия'
  ];

  void _saveCategories() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('selected_categories', _selectedCategories.toList());
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ДИС.Новости'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Приветствуем в ДИС.Новости!\nВыберите 3 и более категорий новостей, которые вас интересуют больше всего.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: _categories.map((category) {
                  return CheckboxListTile(
                    title: Text(category),
                    value: _selectedCategories.contains(category),
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          _selectedCategories.add(category);
                        } else {
                          _selectedCategories.remove(category);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _selectedCategories.length >= 3 ? _saveCategories : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
              child: const Text('Продолжить'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============= ГЛАВНЫЙ ЭКРАН =============
class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  Map<String, dynamic>? _dailyData;
  List<dynamic> _allNews = [];
  List<dynamic> _digestNews = [];
  List<String> _userCategories = [];
  bool _isLoading = true;
  bool _isDigestExpanded = false;
  String? _error;

  final String _serverUrl = "http://201.24.53.232:8000/api/daily";
  final String _yaraUrl = "http://201.24.53.232:8001/api/yara/chat";
  final String _yaraAvatar = "http://201.24.53.232:8000/static/yara.png";

  @override
  void initState() {
    super.initState();
    _loadCategoriesAndData();
  }

  Future<void> _loadCategoriesAndData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _userCategories = prefs.getStringList('selected_categories') ?? [];
    await _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      setState(() => _isLoading = true);
      final response = await http.get(Uri.parse(_serverUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final allNews = data['news'] ?? [];

        List<dynamic> digest = [];
        for (var cat in _userCategories) {
          final found = allNews.firstWhere((n) => n['category'] == cat, orElse: () => null);
          if (found != null) digest.add(found);
        }

        if (digest.length < 3) {
          for (var n in allNews) {
            if (!digest.contains(n) && n['category'] != 'Регион') {
              digest.add(n);
              if (digest.length >= 3) break;
            }
          }
        }

        setState(() {
          _dailyData = data;
          _allNews = allNews;
          _digestNews = digest;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = "Ошибка сервера: ${response.statusCode}";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Не удалось подключиться к серверу";
        _isLoading = false;
      });
    }
  }

  void _openYara(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => YaraScreen(yaraUrl: _yaraUrl, yaraAvatar: _yaraAvatar),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ДИС.Новости'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: ClipOval(
              child: Image.network(
                _yaraAvatar,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.auto_awesome),
              ),
            ),
            tooltip: 'Спроси Яру',
            onPressed: () => _openYara(context),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _dailyData == null
                  ? const Center(child: Text('Нет данных'))
                  : _buildContent(),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Главная'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Новости'),
          BottomNavigationBarItem(icon: Icon(Icons.edit), label: 'Редакция'),
        ],
        onTap: (index) {
          if (index == 1) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => NewsListScreen(news: _allNews)));
          } else if (index == 2) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => EditorialScreen()));
          }
        },
      ),
    );
  }

  Widget _buildContent() {
    final weather = _dailyData!['weather'] ?? {};
    return RefreshIndicator(
      onRefresh: _fetchData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWeatherCard(weather),
            const SizedBox(height: 16),
            _buildDigestSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherCard(Map<String, dynamic> weather) {
    IconData weatherIcon = Icons.wb_sunny;
    String condition = weather['condition'] ?? '';
    if (condition.contains('Дождь') || condition.contains('Ливень') || condition.contains('Морось')) {
      weatherIcon = Icons.grain;
    } else if (condition.contains('Снег')) {
      weatherIcon = Icons.ac_unit;
    } else if (condition.contains('Гроза')) {
      weatherIcon = Icons.flash_on;
    } else if (condition.contains('Туман')) {
      weatherIcon = Icons.foggy;
    } else if (condition.contains('Облачно') || condition.contains('Малооблачно')) {
      weatherIcon = Icons.cloud_queue;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.blue.shade400, Colors.blue.shade700], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(weatherIcon, color: Colors.white, size: 40),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${weather['temp'] ?? '--'}°C', style: const TextStyle(color: Colors.white, fontSize: 24)),
              Text(condition, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDigestSection() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade700], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isDigestExpanded = !_isDigestExpanded),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Ваш персональный дайджест готов',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  Icon(_isDigestExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white),
                ],
              ),
            ),
          ),
          if (_isDigestExpanded) ...[
            ..._digestNews.map((news) => _buildDigestCard(news)),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildDigestCard(Map<String, dynamic> news) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(news['category'] ?? '', style: const TextStyle(color: Colors.deepPurple, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(news['title'] ?? 'Без названия', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(news['description'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          InkWell(
            onTap: () async {
              final url = news['link'] ?? '';
              if (url.isNotEmpty) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            child: const Text('Читать источник →', style: TextStyle(color: Colors.blue, fontSize: 12, decoration: TextDecoration.underline)),
          ),
        ],
      ),
    );
  }
}

// ============= ЭКРАН ВСЕХ НОВОСТЕЙ =============
class NewsListScreen extends StatelessWidget {
  final List<dynamic> news;
  const NewsListScreen({Key? key, required this.news}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Все новости'), centerTitle: true),
      body: news.isEmpty
          ? const Center(child: Text('Новостей пока нет'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: news.length,
              itemBuilder: (context, index) {
                final item = news[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(item['title'] ?? 'Без названия'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(item['description'] ?? '', maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text('Категория: ${item['category'] ?? 'Другое'}', style: const TextStyle(fontSize: 10, color: Colors.blue)),
                      ],
                    ),
                    onTap: () => _showNewsDetail(context, item),
                  ),
                );
              },
            ),
    );
  }

  void _showNewsDetail(BuildContext context, Map<String, dynamic> news) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(news['title'] ?? 'Новость', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(news['description'] ?? 'Описание отсутствует', style: const TextStyle(fontSize: 16, height: 1.5)),
            const SizedBox(height: 16),
            SelectableText(
              news['link'] ?? '',
              style: const TextStyle(color: Colors.blue, fontSize: 14, decoration: TextDecoration.underline),
              onTap: () async {
                final url = news['link'] ?? '';
                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              label: const Text('Закрыть'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============= ЭКРАН РЕДАКЦИИ =============
class EditorialScreen extends StatefulWidget {
  @override
  _EditorialScreenState createState() => _EditorialScreenState();
}

class _EditorialScreenState extends State<EditorialScreen> {
  List<dynamic> _articles = [];
  bool _isLoading = true;
  String? _error;

  final String _editorialUrl = "http://201.24.53.232:8000/api/editorial";

  @override
  void initState() {
    super.initState();
    _fetchEditorial();
  }

  Future<void> _fetchEditorial() async {
    try {
      final response = await http.get(Uri.parse(_editorialUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _articles = data['articles'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = "Ошибка загрузки статей";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Не удалось подключиться к серверу";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Редакция ДИС'), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _articles.isEmpty
                  ? const Center(child: Text('Статей пока нет'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _articles.length,
                      itemBuilder: (context, index) {
                        final article = _articles[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            title: Text(article['title'] ?? 'Без названия'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(article['short_description'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(article['date'] ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              ],
                            ),
                            onTap: () => _showFullArticle(context, article),
                          ),
                        );
                      },
                    ),
    );
  }

  void _showFullArticle(BuildContext context, Map<String, dynamic> article) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(article['title'] ?? 'Статья', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('${article['author'] ?? 'Редакция ДИС'} • ${article['date'] ?? ''}'),
                const Divider(),
                const SizedBox(height: 8),
                Text(article['full_text'] ?? 'Текст отсутствует', style: const TextStyle(fontSize: 16, height: 1.6)),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============= ЭКРАН ЯРЫ (ИИ-помощница) =============
class YaraScreen extends StatefulWidget {
  final String yaraUrl;
  final String yaraAvatar;
  const YaraScreen({Key? key, required this.yaraUrl, required this.yaraAvatar}) : super(key: key);

  @override
  _YaraScreenState createState() => _YaraScreenState();
}

class _YaraScreenState extends State<YaraScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _messages.add({
      "role": "bot",
      "text": "Привет! 👋 Я Яра — твоя умная новостная помощница.\n\nЯ умею:\n• 📰 Искать новости по темам\n• 🌤 Рассказывать о погоде\n• 💱 Показывать курсы валют\n• 🎯 Отвечать на вопросы\n\nСпроси меня о чём-нибудь!"
    });
  }

  Future<void> _sendQuestion() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _isLoading) return;

    setState(() {
      _messages.add({"role": "user", "text": question});
      _isLoading = true;
      _controller.clear();
    });
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse(widget.yaraUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "user_id": "user_default",
          "message": question,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _messages.add({
            "role": "bot",
            "text": data['answer'] ?? 'Не удалось получить ответ.'
          });
          _isLoading = false;
        });
      } else {
        setState(() {
          _messages.add({
            "role": "bot",
            "text": 'Ошибка сервера: ${response.statusCode}'
          });
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _messages.add({
          "role": "bot",
          "text": 'Не удалось подключиться. Проверьте интернет.'
        });
        _isLoading = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)]),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    backgroundImage: NetworkImage(widget.yaraAvatar),
                    radius: 22,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Яра', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Ваша новостная помощница', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isLoading) {
                    return _buildLoadingBubble();
                  }
                  final msg = _messages[index];
                  return _buildMessageBubble(msg['role']!, msg['text']!);
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Напишите вопрос...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onSubmitted: (_) => _sendQuestion(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.deepPurple,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: _isLoading ? null : _sendQuestion,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(String role, String text) {
    final isUser = role == 'user';
    return Row(
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser) ...[
          CircleAvatar(
            radius: 16,
            backgroundImage: NetworkImage(widget.yaraAvatar),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(14),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            decoration: BoxDecoration(
              color: isUser ? Colors.deepPurple : Colors.grey.shade100,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 18),
              ),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isUser ? Colors.white : Colors.black87,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ),
        ),
        if (isUser) ...[
          const SizedBox(width: 8),
          const CircleAvatar(
            radius: 16,
            backgroundColor: Colors.deepPurple,
            child: Icon(Icons.person, color: Colors.white, size: 18),
          ),
        ],
      ],
    );
  }

  Widget _buildLoadingBubble() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundImage: NetworkImage(widget.yaraAvatar),
        ),
        const SizedBox(width: 8),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurple)),
              SizedBox(width: 10),
              Text('Яра думает...', style: TextStyle(color: Colors.grey, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}