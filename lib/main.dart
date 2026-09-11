import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(PulseApp());

class PulseApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ДИС.Новости',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
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
    _checkCategories();
  }

  Future<void> _checkCategories() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? savedCategories = prefs.getStringList('selected_categories');

    if (savedCategories != null && savedCategories.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => MainScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => CategorySelectionScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

// ============= ЭКРАН ВЫБОРА КАТЕГОРИЙ =============
class CategorySelectionScreen extends StatefulWidget {
  @override
  _CategorySelectionScreenState createState() => _CategorySelectionScreenState();
}

class _CategorySelectionScreenState extends State<CategorySelectionScreen> {
  final Set<String> _selectedCategories = {};
  // Категория "Развлечения" убрана!
  final List<String> _categories = [
    'Экономика', 'Технологии', 'Здоровье', 'Спорт', 'Политика', 'Культура'
  ];

  void _saveCategories() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('selected_categories', _selectedCategories.toList());
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MainScreen()),
    );
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
              'Приветствуем в ДИС.Новости!\nПожалуйста, выберите 3 категории новостей, которые вас интересуют больше всего.',
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
  final String _editorialUrl = "http://201.24.53.232:8000/api/editorial";

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

        // Формируем персональный дайджест: по 1 новости из каждой выбранной категории
        List<dynamic> digest = [];
        for (var cat in _userCategories) {
          final found = allNews.firstWhere(
            (n) => n['category'] == cat,
            orElse: () => null,
          );
          if (found != null) digest.add(found);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ДИС.Новости'),
        centerTitle: true,
        actions: [
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
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => NewsListScreen(news: _allNews)));
          } else if (index == 2) {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => EditorialScreen()));
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

  // ===== ПОГОДА С РЕАЛЬНЫМИ ИКОНКАМИ =====
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
    } else {
      weatherIcon = Icons.wb_sunny;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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

  // ===== ПЕРСОНАЛЬНЫЙ ДАЙДЖЕСТ =====
  Widget _buildDigestSection() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isDigestExpanded = !_isDigestExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Ваш персональный дайджест готов',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Icon(
                    _isDigestExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white,
                  ),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            news['category'] ?? '',
            style: const TextStyle(color: Colors.deepPurple, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            news['title'] ?? 'Без названия',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            news['description'] ?? '',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () async {
              final url = news['link'] ?? '';
              if (url.isNotEmpty) {
                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              }
            },
            child: const Text(
              'Читать источник →',
              style: TextStyle(color: Colors.blue, fontSize: 12, decoration: TextDecoration.underline),
            ),
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
                        Text(item['description'] ?? '',
                            maxLines: 4, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text('Категория: ${item['category'] ?? 'Другое'}',
                            style: const TextStyle(fontSize: 10, color: Colors.blue)),
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
                                Text(article['short_description'] ?? '',
                                    maxLines: 2, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(article['date'] ?? '',
                                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Container(
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