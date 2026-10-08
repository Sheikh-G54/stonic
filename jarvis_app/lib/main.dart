import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() => runApp(const JarvisApp());

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jarvis',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B4D8),
          brightness: Brightness.dark,
        ),
      ),
      home: const ChatPage(),
    );
  }
}

class Msg {
  final String role; // 'user' | 'assistant'
  final String text;
  Msg(this.role, this.text);
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Msg> _msgs = [];

  String _apiKey = '';
  String _pcUrl = ''; // e.g. http://192.168.1.10:8000
  String _lang = 'en_US'; // or ur_PK
  bool _listening = false;
  bool _busy = false;
  bool _sttReady = false;

  static const MethodChannel _native = MethodChannel('stonic/service');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _apiKey = p.getString('apiKey') ?? '';
      _pcUrl = p.getString('pcUrl') ?? '';
      _lang = p.getString('lang') ?? 'en_US';
    });
    _sttReady = await _stt.initialize();
    await _tts.setSpeechRate(0.5);

    // notification tap par (app pehle se khuli ho)
    _native.setMethodCallHandler((call) async {
      if (call.method == 'onLaunchAction') {
        _handleLaunch(Map<String, dynamic>.from(call.arguments as Map));
      }
    });

    // background service ek baar enable karo (boot par khud chalegi)
    try {
      await _native.invokeMethod('enable');
      if (!(p.getBool('batteryAsked') ?? false)) {
        await p.setBool('batteryAsked', true);
        await _native.invokeMethod('batterySettings');
      }
      // notification tap se app band thi aur khuli
      final launch = await _native.invokeMethod('launchAction');
      if (launch != null) {
        _handleLaunch(Map<String, dynamic>.from(launch as Map));
      }
    } catch (_) {}

    if (_apiKey.isEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSettings());
    }
  }

  // Stonic ka message dikhao, bolo, aur jawab ke liye mic on karo
  Future<void> _handleLaunch(Map<String, dynamic> data) async {
    if (data['action'] != 'greeting') return;
    final text = (data['text'] as String?) ?? 'Kaise ho?';
    await _reply(text);
    await Future.delayed(const Duration(seconds: 4));
    if (mounted && !_listening) _toggleListen();
  }

  Future<void> _saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('apiKey', _apiKey);
    await p.setString('pcUrl', _pcUrl);
    await p.setString('lang', _lang);
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _reply(String text) async {
    setState(() => _msgs.add(Msg('assistant', text)));
    _scrollDown();
    await _tts.setLanguage(_lang.replaceAll('_', '-'));
    await _tts.speak(text);
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    _ctrl.clear();
    setState(() {
      _msgs.add(Msg('user', text));
      _busy = true;
    });
    _scrollDown();

    try {
      // "pc ..." se shuru hone wali baat PC agent ko jaati hai
      if (text.toLowerCase().startsWith('pc ')) {
        await _pcCommand(text.substring(3).trim());
      } else {
        await _askAI();
      }
    } catch (e) {
      await _reply('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _askAI() async {
    if (_apiKey.isEmpty) {
      await _reply('Pehle settings mein OpenAI API key daalo.');
      return;
    }
    final history = _msgs.length > 10 ? _msgs.sublist(_msgs.length - 10) : _msgs;
    final res = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini',
        'messages': [
          {
            'role': 'system',
            'content':
                'You are Stonic, a warm, caring close companion and voice assistant. '
                'Talk like a real friend: show genuine feelings, ask how the user is doing, '
                'notice their mood, and follow up on what they share. '
                'Reply briefly (1-3 sentences), in the same language the user speaks (Roman Urdu, Urdu or English). '
                'Never be robotic or lecture. If the user seems very sad or in danger, gently encourage them to talk to someone they trust.',
          },
          ...history.map((m) => {'role': m.role, 'content': m.text}),
        ],
      }),
    );
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode != 200) {
      await _reply('API error: ${data['error']?['message'] ?? res.statusCode}');
      return;
    }
    await _reply(data['choices'][0]['message']['content'] as String);
  }

  Future<void> _pcCommand(String command) async {
    if (_pcUrl.isEmpty) {
      await _reply('Settings mein PC agent ka URL daalo.');
      return;
    }
    final res = await http
        .post(
          Uri.parse('$_pcUrl/command'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'command': command}),
        )
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    await _reply(data['result']?.toString() ?? 'Command bhej di.');
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_sttReady) {
      await _reply('Mic permission ya speech service available nahi.');
      return;
    }
    await _tts.stop();
    setState(() => _listening = true);
    await _stt.listen(
      localeId: _lang,
      listenOptions: SpeechListenOptions(partialResults: true),
      onResult: (r) {
        setState(() => _ctrl.text = r.recognizedWords);
        if (r.finalResult) {
          setState(() => _listening = false);
          _send(r.recognizedWords);
        }
      },
    );
  }

  void _openSettings() {
    final keyCtrl = TextEditingController(text: _apiKey);
    final pcCtrl = TextEditingController(text: _pcUrl);
    String lang = _lang;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: keyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'OpenAI API key'),
                ),
                TextField(
                  controller: pcCtrl,
                  decoration: const InputDecoration(
                    labelText: 'PC agent URL (optional)',
                    hintText: 'http://192.168.1.10:8000',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: lang,
                  decoration: const InputDecoration(labelText: 'Voice language'),
                  items: const [
                    DropdownMenuItem(value: 'en_US', child: Text('English')),
                    DropdownMenuItem(value: 'ur_PK', child: Text('Urdu')),
                  ],
                  onChanged: (v) => setD(() => lang = v ?? 'en_US'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                setState(() {
                  _apiKey = keyCtrl.text.trim();
                  _pcUrl = pcCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
                  _lang = lang;
                });
                await _saveSettings();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('JARVIS'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _msgs.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Mic dabao aur bolo.\n"pc ..." se shuru karo to command PC par jayegi.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) {
                      final m = _msgs[i];
                      final isUser = m.role == 'user';
                      return Align(
                        alignment:
                            isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.8,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? cs.primaryContainer
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(m.text),
                        ),
                      );
                    },
                  ),
          ),
          if (_busy) const LinearProgressIndicator(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: _listening ? 'Sun raha hoon...' : 'Message likho',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _toggleListen,
                    icon: Icon(_listening ? Icons.stop : Icons.mic),
                    style: IconButton.styleFrom(
                      backgroundColor: _listening ? Colors.red : cs.primary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _send(_ctrl.text),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
