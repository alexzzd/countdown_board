import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const WindowOptions windowOptions = WindowOptions(
    fullScreen: true,
    backgroundColor: Colors.black,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const CountdownApp());
}

class CountdownApp extends StatelessWidget {
  const CountdownApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CountdownScreen(),
    );
  }
}

class Speaker {
  Speaker({required this.name, required this.seconds});

  final String name;
  final int seconds;

  Map<String, dynamic> toJson() => {
        'name': name,
        'seconds': seconds,
      };

  factory Speaker.fromJson(Map<String, dynamic> json) {
    final seconds = (json['seconds'] as num?)?.toInt() ??
        ((json['minutes'] as num?)?.toInt() ?? 0) * 60;
    return Speaker(
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Докладчик',
      seconds: seconds < 0 ? 0 : seconds,
    );
  }
}

class CountdownScreen extends StatefulWidget {
  const CountdownScreen({super.key});

  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen>
    with TickerProviderStateMixin {
  static const String _prefsSpeakersKey = 'speakers';
  static const String _prefsSelectedIndexKey = 'selectedIndex';

  DateTime? _endTime;
  Timer? _ticker;
  HttpServer? _server;

  int _remainingSeconds = 0;
  int _selectedIndex = -1;
  List<Speaker> _speakers = [];

  late AnimationController _blinkController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: 0.0,
      upperBound: 1.0,
    )..repeat(reverse: true);

    _initialize();
  }

  Future<void> _initialize() async {
    await _loadFromPrefs();
    _startTicker();
    _startApiServer();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final rawSpeakers = prefs.getString(_prefsSpeakersKey);
    final selectedIndex = prefs.getInt(_prefsSelectedIndexKey) ?? -1;

    List<Speaker> speakers = [];
    if (rawSpeakers != null && rawSpeakers.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSpeakers) as List<dynamic>;
        speakers = decoded
            .map((item) => Speaker.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (_) {
        speakers = [];
      }
    }

    int validSelectedIndex = selectedIndex;
    if (validSelectedIndex < 0 || validSelectedIndex >= speakers.length) {
      validSelectedIndex = -1;
    }

    setState(() {
      _speakers = speakers;
      _selectedIndex = validSelectedIndex;
      _remainingSeconds =
          validSelectedIndex >= 0 ? _speakers[validSelectedIndex].seconds : 0;
    });
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_speakers.map((s) => s.toJson()).toList());
    await prefs.setString(_prefsSpeakersKey, encoded);
    await prefs.setInt(_prefsSelectedIndexKey, _selectedIndex);
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_isRunning) {
        final diff = _endTime!.difference(DateTime.now()).inSeconds;
        if (diff <= 0) {
          setState(() {
            _endTime = null;
            _remainingSeconds = 0;
          });
          return;
        }
      }
      setState(() {});
    });
  }

  int get _secondsLeft {
    if (_isRunning) {
      final diff = _endTime!.difference(DateTime.now()).inSeconds;
      return diff > 0 ? diff : 0;
    }
    return _remainingSeconds > 0 ? _remainingSeconds : 0;
  }

  bool get _isRunning => _endTime != null;

  bool get _isFinished => !_isRunning && _remainingSeconds == 0;

  bool get _isLastMinute => _isRunning && _secondsLeft <= 60;

  String get _formattedTime {
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  void _selectSpeaker(int index) {
    setState(() {
      if (index < 0 || index >= _speakers.length) {
        _selectedIndex = -1;
        _remainingSeconds = 0;
        _endTime = null;
        return;
      }
      _selectedIndex = index;
      _remainingSeconds = _speakers[index].seconds;
      _endTime = DateTime.now().add(Duration(seconds: _remainingSeconds));
    });
    _saveToPrefs();
  }

  void _selectSpeakerIdle(int index) {
    setState(() {
      if (index < 0 || index >= _speakers.length) {
        _selectedIndex = -1;
        _remainingSeconds = 0;
        _endTime = null;
        return;
      }
      _selectedIndex = index;
      _remainingSeconds = _speakers[index].seconds;
      _endTime = null;
    });
    _saveToPrefs();
  }

  void _updateSpeakers(List<Speaker> speakers) {
    setState(() {
      _speakers = speakers;
      if (_selectedIndex >= _speakers.length) {
        _selectedIndex = -1;
      }
      if (!_isRunning) {
        _remainingSeconds = _selectedIndex >= 0
            ? _speakers[_selectedIndex].seconds
            : 0;
      }
    });
    _saveToPrefs();
  }

  void _startTimer() {
    if (_isRunning) return;

    if (_selectedIndex < 0 && _speakers.isNotEmpty) {
      _selectedIndex = 0;
    }

    if (_selectedIndex < 0 || _selectedIndex >= _speakers.length) {
      setState(() {
        _remainingSeconds = 0;
      });
      return;
    }

    if (_remainingSeconds <= 0) {
      _remainingSeconds = _speakers[_selectedIndex].seconds;
    }

    setState(() {
      _endTime = DateTime.now().add(Duration(seconds: _remainingSeconds));
    });
    _saveToPrefs();
  }

  void _stopTimer() {
    if (!_isRunning) return;
    final diff = _endTime!.difference(DateTime.now()).inSeconds;
    setState(() {
      _remainingSeconds = diff > 0 ? diff : 0;
      _endTime = null;
    });
  }

  void _resetTimer() {
    setState(() {
      _endTime = null;
      if (_selectedIndex >= 0 && _selectedIndex < _speakers.length) {
        _remainingSeconds = _speakers[_selectedIndex].seconds;
      } else {
        _remainingSeconds = 0;
      }
    });
  }

  Future<void> _startApiServer() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 3000);
    _server = server;

    await for (HttpRequest request in server) {
      final path = request.uri.path;

      if (path == '/' || path.isEmpty) {
        request.response.headers.contentType = ContentType.html;
        request.response.write(_adminHtml);
        await request.response.close();
        continue;
      }

      if (path == '/api/status') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'secondsLeft': _secondsLeft,
            'running': _isRunning,
            'selectedIndex': _selectedIndex,
            'speakerName': _selectedIndex >= 0 && _selectedIndex < _speakers.length
                ? _speakers[_selectedIndex].name
                : null,
          }),
        );
        await request.response.close();
        continue;
      }

      if (path == '/api/speakers') {
        if (request.method == 'GET') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'selectedIndex': _selectedIndex,
              'speakers': _speakers
                  .map((speaker) => {
                        'name': speaker.name,
                        'seconds': speaker.seconds,
                        'minutes': (speaker.seconds / 60).round(),
                      })
                  .toList(),
            }),
          );
          await request.response.close();
          continue;
        }

        if (request.method == 'POST') {
          final body = await utf8.decoder.bind(request).join();
          try {
            final data = jsonDecode(body) as Map<String, dynamic>;
            final items = (data['speakers'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>();
            final speakers = items.map(Speaker.fromJson).toList();
            final selected = (data['selectedIndex'] as num?)?.toInt();

            _updateSpeakers(speakers);
            if (selected != null) {
              _selectSpeaker(selected);
            }
            request.response.write('OK');
          } catch (_) {
            request.response.statusCode = HttpStatus.badRequest;
            request.response.write('Invalid JSON');
          }
          await request.response.close();
          continue;
        }
      }

      if (path == '/api/select') {
        final index =
            int.tryParse(request.uri.queryParameters['index'] ?? '') ?? -1;
        _selectSpeaker(index);
        request.response.write('OK');
        await request.response.close();
        continue;
      }

      if (path == '/api/select-idle') {
        final index =
            int.tryParse(request.uri.queryParameters['index'] ?? '') ?? -1;
        _selectSpeakerIdle(index);
        request.response.write('OK');
        await request.response.close();
        continue;
      }

      if (path == '/api/start') {
        _startTimer();
        request.response.write('OK');
        await request.response.close();
        continue;
      }

      if (path == '/api/stop') {
        _stopTimer();
        request.response.write('OK');
        await request.response.close();
        continue;
      }

      if (path == '/api/reset') {
        _resetTimer();
        request.response.write('OK');
        await request.response.close();
        continue;
      }

      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Not Found');
      await request.response.close();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _server?.close(force: true);
    _blinkController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool blink = _isFinished;
    final double opacity = blink ? _blinkController.value : 1.0;

    final bool pulse = _isLastMinute && !_isFinished;
    final double pulseScale = pulse ? (1.0 + 0.08 * _pulseController.value) : 1.0;
    final List<Shadow> glow = pulse
        ? [
            const Shadow(color: Colors.redAccent, blurRadius: 40),
            const Shadow(color: Colors.redAccent, blurRadius: 80),
          ]
        : [];

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: _isFinished ? Colors.red.withValues(alpha: opacity) : Colors.black,
        child: Stack(
          children: [
            Positioned(
              top: 24,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topCenter,
                child: Image.asset(
                  'assets/images/neurologo.png',
                  height: 180,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Center(
              child: Opacity(
                opacity: blink ? opacity : 1.0,
                child: Transform.scale(
                  scale: pulseScale,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Text(
                      _formattedTime,
                      style: GoogleFonts.googleSansCode(
                        fontSize: 1000,
                        fontWeight: FontWeight.w500,
                        color: pulse ? Colors.redAccent : Colors.white,
                        shadows: glow,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const String _adminHtml = r'''
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Countdown Board Control</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 24px; color: #222; }
    h1 { margin-bottom: 8px; }
    .status { margin: 12px 0 20px; padding: 12px; background: #f3f3f3; border-radius: 8px; }
    .controls button { margin-right: 8px; padding: 10px 14px; }
    table { border-collapse: collapse; width: 100%; margin-top: 12px; }
    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
    tr.selected { background: #e8f3ff; }
    input[type="text"], input[type="number"] { width: 100%; padding: 6px; }
    .row-actions button { margin-right: 6px; }
  </style>
</head>
<body>
  <h1>Управление таймером</h1>
  <div class="status">
    <div id="statusText">Загрузка...</div>
  </div>

  <div class="controls">
    <button onclick="startTimer()">Старт</button>
    <button onclick="stopTimer()">Стоп</button>
    <button onclick="resetTimer()">Сброс</button>
  </div>

  <h2>Докладчики</h2>
  <button onclick="addSpeaker()">Добавить</button>
  <button onclick="saveSpeakers()">Сохранить список</button>

  <table>
    <thead>
      <tr>
        <th>Имя</th>
        <th>Минуты</th>
        <th>Выбор</th>
        <th>Действия</th>
      </tr>
    </thead>
    <tbody id="speakersBody"></tbody>
  </table>

  <script>
    let speakers = [];
    let selectedIndex = -1;
    let isRunning = false;

    function formatTime(sec) {
      const minutes = Math.floor(sec / 60);
      const seconds = sec % 60;
      return String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0');
    }

    async function loadSpeakers() {
      const res = await fetch('/api/speakers');
      const data = await res.json();
      speakers = data.speakers || [];
      selectedIndex = Number.isInteger(data.selectedIndex) ? data.selectedIndex : -1;
      renderTable();
    }

    function renderTable() {
      const tbody = document.getElementById('speakersBody');
      tbody.innerHTML = '';

      speakers.forEach((speaker, index) => {
        const tr = document.createElement('tr');
        if (index === selectedIndex) {
          tr.classList.add('selected');
        }

        const nameTd = document.createElement('td');
        const nameInput = document.createElement('input');
        nameInput.type = 'text';
        nameInput.value = speaker.name || '';
        nameInput.addEventListener('input', (e) => {
          speakers[index].name = e.target.value;
        });
        nameTd.appendChild(nameInput);

        const minutesTd = document.createElement('td');
        const minutesInput = document.createElement('input');
        minutesInput.type = 'number';
        minutesInput.min = '0';
        minutesInput.value = Math.round((speaker.seconds || 0) / 60);
        minutesInput.addEventListener('input', (e) => {
          const value = parseInt(e.target.value || '0', 10);
          speakers[index].seconds = isNaN(value) ? 0 : value * 60;
        });
        minutesTd.appendChild(minutesInput);

        const selectTd = document.createElement('td');
        const selectBtn = document.createElement('button');
        const isSelected = index === selectedIndex;
        selectBtn.textContent = isSelected && isRunning ? 'Запущен' : 'Запустить';
        selectBtn.onclick = () => selectSpeaker(index);
        selectTd.appendChild(selectBtn);

        const idleBtn = document.createElement('button');
        idleBtn.textContent = isSelected ? 'Выбран' : 'Выбор';
        idleBtn.onclick = () => selectSpeakerIdle(index);
        selectTd.appendChild(idleBtn);

        const actionsTd = document.createElement('td');
        actionsTd.className = 'row-actions';
        const removeBtn = document.createElement('button');
        removeBtn.textContent = 'Удалить';
        removeBtn.onclick = () => removeSpeaker(index);
        actionsTd.appendChild(removeBtn);

        tr.appendChild(nameTd);
        tr.appendChild(minutesTd);
        tr.appendChild(selectTd);
        tr.appendChild(actionsTd);
        tbody.appendChild(tr);
      });
    }

    function addSpeaker() {
      speakers.push({ name: 'Докладчик', seconds: 300 });
      renderTable();
    }

    function removeSpeaker(index) {
      speakers.splice(index, 1);
      if (selectedIndex === index) {
        selectedIndex = -1;
      } else if (selectedIndex > index) {
        selectedIndex -= 1;
      }
      renderTable();
    }

    async function saveSpeakers() {
      await fetch('/api/speakers', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ speakers })
      });
      await loadSpeakers();
    }

    async function selectSpeaker(index) {
      await fetch('/api/select?index=' + index, { method: 'POST' });
      await loadSpeakers();
    }

    async function selectSpeakerIdle(index) {
      await fetch('/api/select-idle?index=' + index, { method: 'POST' });
      await loadSpeakers();
    }

    async function startTimer() {
      await fetch('/api/start', { method: 'POST' });
    }

    async function stopTimer() {
      await fetch('/api/stop', { method: 'POST' });
    }

    async function resetTimer() {
      await fetch('/api/reset', { method: 'POST' });
    }

    async function pollStatus() {
      try {
        const res = await fetch('/api/status');
        const data = await res.json();
        isRunning = !!data.running;
        const status = data.running ? 'Идёт' : 'Остановлен';
        const name = data.speakerName ? `Докладчик: ${data.speakerName}` : 'Докладчик не выбран';
        document.getElementById('statusText').textContent = `${status} | ${formatTime(data.secondsLeft || 0)} | ${name}`;
        renderTable();
      } catch (_) {
        document.getElementById('statusText').textContent = 'Нет соединения';
      }
    }

    loadSpeakers();
    pollStatus();
    setInterval(pollStatus, 1000);
  </script>
</body>
</html>
''';
