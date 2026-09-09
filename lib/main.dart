import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(PulseApp());

class PulseApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ДИС',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  Map<String, dynamic>? _dailyData;
  List<dynamic> _allNews = [];
  bool _isLoading = true;
  String? _error;

  // Прямая ссылка на сервер (HTTP разрешен)
  final String _serverUrl = "http://201.24.53.232:8000/api/daily";
  final String _allNewsUrl = "http://201.24.53.232:8000/api/daily";
  final String _editorialUrl = "http://201.24.53.232:8000/api/editorial";

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      setState(() => _isLoading = true);
      final response = await http.get(Uri.parse(_serverUrl));
      if (response.statusCode == 200) {
        setState(() {
          _dailyData = json.decode(response.body);
          _allNews = _dailyData?['news'] ?? [];
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
        title: const Text('ДИС'),
        centerTitle: true,
        elevation: 0,
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
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NewsListScreen(news: _allNews),
              ),
            );
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => EditorialScreen()),
            );
          }
        },
      ),
    );
  }

  Widget _buildContent() {
    final weather = _dailyData!['weather'] ?? {};
    final news = _dailyData!['news'] ?? [];

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWeatherCard(weather),
            const SizedBox(height: 16),
            const Text('Главные новости', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...news.take(4).map((item) => _buildNewsCard(item)),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NewsListScreen(news: _allNews),
                    ),
                  );
                },
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Все новости'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherCard(Map<String, dynamic> weather) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          const Icon(Icons.wb_sunny, color: Colors.white, size: 40),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${weather['temp'] ?? '--'}°C', style: const TextStyle(color: Colors.white, fontSize: 24)),
              Text(weather['condition'] ?? 'ясно', style: const TextStyle(color: Colors.white70)),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.directions_car, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text('${weather['traffic'] ?? '--'} баллов', style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsCard(Map<String, dynamic> news) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        title: Text(news['title'] ?? 'Без названия', maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              news['description'] ?? '',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              'Источник: ${news['source'] ?? 'неизвестен'}',
              style: const TextStyle(fontSize: 10, color: Colors.blue),
            ),
          ],
        ),
        onTap: () {
          _showNewsDetail(context, news);
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
            Row(
              children: [
                const Icon(Icons.link, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    news['link'] ?? '',
                    style: const TextStyle(color: Colors.blue, fontSize: 14, decoration: TextDecoration.underline),
                    onTap: () async {
                      final url = news['link'] ?? '';
                      await launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                ),
              ],
            ),
            const Spacer(),
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
                        Text(
                          item['description'] ?? '',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Категория: ${item['category'] ?? 'Другое'}',
                          style: const TextStyle(fontSize: 10, color: Colors.blue),
                        ),
                      ],
                    ),
                    onTap: () {
                      _showNewsDetail(context, item);
                    },
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
            Row(
              children: [
                const Icon(Icons.link, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    news['link'] ?? '',
                    style: const TextStyle(color: Colors.blue, fontSize: 14, decoration: TextDecoration.underline),
                    onTap: () async {
                      final url = news['link'] ?? '';
                      await launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                ),
              ],
            ),
            const Spacer(),
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
      setState(() => _isLoading = true);
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
      appBar: AppBar(title: const Text('Редакция Пульс'), centerTitle: true),
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
                                Text(
                                  article['short_description'] ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  article['date'] ?? '',
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                            onTap: () {
                              _showFullArticle(context, article);
                            },
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
                Text('${article['author'] ?? 'Редакция Пульс'} • ${article['date'] ?? ''}'),
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
