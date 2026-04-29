import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() {
  runApp(const DeviceControllerApp());
}

class DeviceControllerApp extends StatelessWidget {
  const DeviceControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WiFi+Bel 3Gang',
      theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
      home: const GlassSwitchPage(),
    );
  }
}

class GlassSwitchPage extends StatefulWidget {
  const GlassSwitchPage({super.key});

  @override
  State<GlassSwitchPage> createState() => _GlassSwitchPageState();
}

class _GlassSwitchPageState extends State<GlassSwitchPage> {
  final EspApiClient api = EspApiClient();
  final SpeechToText speech = SpeechToText();

  List<bool> states = [false, false, false];
  List<int> timerSeconds = [0, 0, 0];
  bool connected = false;
  bool listening = false;
  String heard = '';
  String firmwareVersion = '--';
  String connectionText = 'Dang tim ESP32-C3...';
  Timer? syncTimer;

  static const labels = ['Den', 'Quat', 'Switch 3'];
  static const timerMinutes = [1, 5, 15, 30, 60, 120];

  @override
  void initState() {
    super.initState();
    initFlow();
  }

  Future<void> initFlow() async {
    await api.autoDiscoverBaseUrl();
    await refreshStatus();
    syncTimer = Timer.periodic(const Duration(seconds: 3), (_) => refreshStatus());
  }

  @override
  void dispose() {
    syncTimer?.cancel();
    speech.stop();
    super.dispose();
  }

  Future<void> refreshStatus() async {
    final status = await api.getStatus();
    if (!mounted) return;

    if (status != null) {
      setState(() {
        states = status.switches;
        timerSeconds = status.timerSeconds;
        firmwareVersion = status.firmwareVersion;
        connectionText = status.connectionText;
        connected = true;
      });
    } else {
      setState(() {
        connected = false;
        connectionText = 'Mat ket noi';
      });
    }
  }

  Future<void> openSettingsSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0C1A23),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Setting',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ket noi: $connectionText',
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                    const SizedBox(height: 6),
                    Text('Firmware: v$firmwareVersion',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final result = await api.checkAndUpdateFirmware();
                  if (!mounted) return;
                  toast(result);
                  await refreshStatus();
                },
                child: const Text('Cap nhat phan mem'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> setSwitch(int i, bool next) async {
    final ok = await api.toggle(i, next);
    if (!mounted) return;
    if (ok) {
      await refreshStatus();
    } else {
      toast('Khong gui duoc lenh');
    }
  }

  Future<void> switchAll(bool on) async {
    final ok = await api.switchAll(on);
    if (!mounted) return;
    if (ok) {
      await refreshStatus();
    } else {
      toast('Lenh ALL that bai');
    }
  }

  Future<void> applyTimer(int device, int minutes) async {
    final ok = await api.setTimer(device, minutes);
    if (!mounted) return;
    if (ok) {
      toast('Hen gio ${labels[device]} $minutes phut');
      await refreshStatus();
    } else {
      toast('Hen gio that bai');
    }
  }

  void toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String timerLabel(int sec) {
    if (sec <= 0) return '';
    if (sec >= 3600) {
      final h = sec ~/ 3600;
      final m = (sec % 3600) ~/ 60;
      return m == 0 ? '${h}h' : '${h}h ${m}m';
    }
    return '${(sec / 60).ceil()}m';
  }

  Future<void> startVoice() async {
    if (!listening) {
      final available = await speech.initialize(
        onStatus: (_) {},
        onError: (e) => toast('Voice loi: ${e.errorMsg}'),
      );
      if (!available) {
        toast('May khong ho tro voice');
        return;
      }
      setState(() => listening = true);
      await speech.listen(onResult: onVoiceResult, localeId: 'vi_VN');
    } else {
      await speech.stop();
      setState(() => listening = false);
    }
  }

  Future<void> onVoiceResult(SpeechRecognitionResult result) async {
    setState(() => heard = result.recognizedWords.toLowerCase());
    if (!result.finalResult) return;

    final text = heard;
    await speech.stop();
    setState(() => listening = false);

    int device = 0;
    if (text.contains('quat')) device = 1;
    if (text.contains('switch 3') || text.contains('cong tac 3')) device = 2;

    if (text.contains('bat tat ca') || text.contains('all on')) {
      await switchAll(true);
      return;
    }
    if (text.contains('tat tat ca') || text.contains('all off')) {
      await switchAll(false);
      return;
    }
    if (text.contains('bat')) {
      await setSwitch(device, true);
      return;
    }
    if (text.contains('tat')) {
      await setSwitch(device, false);
      return;
    }

    final reg = RegExp(r'(\d+)');
    final match = reg.firstMatch(text);
    if (text.contains('hen gio') && match != null) {
      final m = int.tryParse(match.group(1) ?? '0') ?? 0;
      if (m > 0) {
        await applyTimer(device, m);
        return;
      }
    }

    toast('Khong hieu lenh: "$text"');
  }

  Future<void> openTimerSheet() async {
    int pickedDevice = 0;
    int pickedMin = 15;

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0C1A23),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setBottomState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Hen gio', style: TextStyle(color: Colors.white, fontSize: 20)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: pickedDevice,
                    dropdownColor: const Color(0xFF1A2A34),
                    decoration: boxDeco('Thiet bi'),
                    items: List.generate(
                      labels.length,
                      (i) => DropdownMenuItem(value: i, child: Text(labels[i])),
                    ),
                    onChanged: (v) => setBottomState(() => pickedDevice = v ?? 0),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: pickedMin,
                    dropdownColor: const Color(0xFF1A2A34),
                    decoration: boxDeco('So phut'),
                    items: timerMinutes
                        .map((m) => DropdownMenuItem(
                            value: m, child: Text(m >= 60 ? '${m ~/ 60}h' : '${m}m')))
                        .toList(),
                    onChanged: (v) => setBottomState(() => pickedMin = v ?? 15),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await applyTimer(pickedDevice, pickedMin);
                    },
                    child: const Text('Ap dung'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  InputDecoration boxDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
      ),
      border: const OutlineInputBorder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _StarBackground(),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 50),
                    const Text(
                      'WiFi+Bel 3gang',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: refreshStatus,
                          icon: Icon(
                            connected ? Icons.more_horiz : Icons.wifi_off,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          onPressed: startVoice,
                          icon: Icon(
                            listening ? Icons.mic : Icons.mic_none,
                            color: listening ? Colors.amber : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (heard.isNotEmpty)
                  Text('Voice: $heard', style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: Colors.black.withValues(alpha: 0.35),
                    border: Border.all(
                      color: connected
                          ? const Color(0xFF44E0B2).withValues(alpha: 0.7)
                          : Colors.orange.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        connected ? Icons.wifi : Icons.wifi_off,
                        color: connected ? const Color(0xFF44E0B2) : Colors.orange,
                        size: 15,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          connectionText,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: List.generate(3, (i) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _GlassSwitchCard(
                            label: labels[i],
                            on: states[i],
                            timer: timerLabel(timerSeconds[i]),
                            onTap: () => setSwitch(i, !states[i]),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  color: Colors.black.withValues(alpha: 0.35),
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      BottomBtn(title: 'All On', icon: 'ON', onTap: () => switchAll(true)),
                      BottomBtn(title: 'Timer', icon: '⏲', onTap: openTimerSheet),
                      BottomBtn(title: 'Setting', icon: '◻', onTap: openSettingsSheet),
                      BottomBtn(title: 'All Off', icon: 'OFF', onTap: () => switchAll(false)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BottomBtn extends StatelessWidget {
  const BottomBtn({super.key, required this.title, required this.icon, required this.onTap});

  final String title;
  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(icon, style: const TextStyle(color: Colors.white, fontSize: 28)),
            ),
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18)),
        ],
      ),
    );
  }
}

class _GlassSwitchCard extends StatelessWidget {
  const _GlassSwitchCard({
    required this.label,
    required this.on,
    required this.timer,
    required this.onTap,
  });

  final String label;
  final bool on;
  final String timer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 460,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: on
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x5527D5D8), Color(0xCC2AD1D0)],
                    )
                  : const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x222F3943), Color(0x88424F5B)],
                    ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 2),
              boxShadow: [
                if (on)
                  BoxShadow(
                    color: const Color(0xFF35E2DB).withValues(alpha: 0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
              ],
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Container(
                  width: 52,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: on ? Colors.yellow.shade600 : Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 20)),
        if (timer.isNotEmpty)
          Text(timer, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}

class _StarBackground extends StatelessWidget {
  const _StarBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF021A24), Color(0xFF042C35), Color(0xFF011017)],
        ),
      ),
      child: CustomPaint(painter: StarPainter(), size: Size.infinite),
    );
  }
}

class StarPainter extends CustomPainter {
  final rnd = Random(7);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.35);
    for (int i = 0; i < 260; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height * 0.8;
      final r = rnd.nextDouble() * 1.6;
      canvas.drawCircle(Offset(dx, dy), r, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DeviceStatus {
  DeviceStatus({
    required this.switches,
    required this.timerSeconds,
    required this.firmwareVersion,
    required this.connectionText,
  });

  final List<bool> switches;
  final List<int> timerSeconds;
  final String firmwareVersion;
  final String connectionText;

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    final rawSwitches = (json['switches'] as List<dynamic>? ?? const [0, 0, 0]);
    final rawTimers = (json['timers'] as List<dynamic>? ?? const []);

    final switches = rawSwitches.take(3).map((e) => e == true || e == 1).toList();
    while (switches.length < 3) {
      switches.add(false);
    }

    final timers = List<int>.filled(3, 0);
    for (var i = 0; i < rawTimers.length && i < 3; i++) {
      final timer = rawTimers[i] as Map<String, dynamic>?;
      if (timer != null && timer['active'] == true) {
        timers[i] = (timer['remaining'] as num?)?.toInt() ?? 0;
      }
    }
    final firmware = (json['fw'] ?? json['firmware'] ?? json['version'] ?? '--').toString();
    final ip = (json['ip'] ?? json['local_ip'] ?? '').toString();
    final wifi = (json['wifi'] ?? json['ssid'] ?? '').toString();
    final conn = ip.isNotEmpty
        ? 'Da ket noi $ip'
        : wifi.isNotEmpty
            ? 'WiFi: $wifi'
            : 'Da ket noi ESP32-C3';
    return DeviceStatus(
      switches: switches,
      timerSeconds: timers,
      firmwareVersion: firmware,
      connectionText: conn,
    );
  }
}

class EspApiClient {
  String? baseUrl;

  Future<void> autoDiscoverBaseUrl() async {
    final endpoints = <String>[];

    final mdns = MDnsClient();
    try {
      await mdns.start();
      await for (final ptr in mdns.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_http._tcp.local'),
      ).timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
        await for (final srv in mdns.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        ).timeout(const Duration(milliseconds: 800), onTimeout: (sink) => sink.close())) {
          final host = srv.target;
          final port = srv.port;
          await for (final ip in mdns.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(host),
          ).timeout(const Duration(milliseconds: 800), onTimeout: (sink) => sink.close())) {
            endpoints.add('http://${ip.address.address}:$port');
          }
        }
      }
    } catch (_) {
      // fallback ben duoi
    } finally {
      mdns.stop();
    }

    endpoints.addAll(['http://esp32c3.local', 'http://esp32.local', 'http://192.168.4.1']);

    for (final url in endpoints.toSet()) {
      final ok = await _ping(url);
      if (ok) {
        baseUrl = url;
        return;
      }
    }
  }

  Future<bool> _ping(String url) async {
    try {
      final response = await http.get(Uri.parse('$url/status')).timeout(const Duration(seconds: 1));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<DeviceStatus?> getStatus() async {
    final json = await _request('GET', '/status');
    if (json == null) return null;

    try {
      return DeviceStatus.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<bool> toggle(int id, bool state) async {
    final res = await _request('POST', '/toggle', body: {'id': id, 'state': state});
    return res != null;
  }

  Future<bool> switchAll(bool state) async {
    final res = await _request('POST', '/all', body: {'state': state});
    return res != null;
  }

  Future<bool> setTimer(int id, int minutes) async {
    final res = await _request('POST', '/timer', body: {'id': id, 'minutes': minutes});
    return res != null;
  }

  Future<String> checkAndUpdateFirmware() async {
    final info = await _request('GET', '/fw');
    if (info == null) {
      return 'Khong lay duoc thong tin firmware';
    }

    final hasUpdate = info['has_update'] == true || info['update'] == true;
    if (!hasUpdate) {
      return 'Phan mem da moi nhat';
    }

    final res = await _request('POST', '/update');
    if (res == null) {
      return 'Cap nhat that bai';
    }
    return 'Da gui lenh cap nhat. ESP32-C3 se khoi dong lai';
  }

  Future<Map<String, dynamic>?> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final base = baseUrl;
    if (base == null) return null;
    final uri = Uri.parse('$base$path');

    try {
      final response = method == 'GET'
          ? await http.get(uri).timeout(const Duration(seconds: 2))
          : await http
              .post(
                uri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(body ?? const {}),
              )
              .timeout(const Duration(seconds: 2));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) return parsed;
      return {};
    } catch (_) {
      return null;
    }
  }
}
