import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Erreur renvoyée par le routeur ou par la couche réseau.
class RouterOsException implements Exception {
  RouterOsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Réponse complète à une commande : lignes `!re` + attributs du `!done`.
class ApiReply {
  ApiReply(this.rows, this.done);
  final List<Map<String, String>> rows;
  final Map<String, String> done;
}

// ---------------------------------------------------------------------------
// Encodage du protocole API RouterOS
// ---------------------------------------------------------------------------

/// Encode la longueur d'un mot (1 à 5 octets selon la taille).
Uint8List encodeLength(int len) {
  if (len < 0) throw ArgumentError.value(len, 'len');
  if (len < 0x80) {
    return Uint8List.fromList([len]);
  }
  if (len < 0x4000) {
    final v = len | 0x8000;
    return Uint8List.fromList([(v >> 8) & 0xFF, v & 0xFF]);
  }
  if (len < 0x200000) {
    final v = len | 0xC00000;
    return Uint8List.fromList([(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
  }
  if (len < 0x10000000) {
    final v = len | 0xE0000000;
    return Uint8List.fromList(
        [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
  }
  return Uint8List.fromList([
    0xF0,
    (len >> 24) & 0xFF,
    (len >> 16) & 0xFF,
    (len >> 8) & 0xFF,
    len & 0xFF,
  ]);
}

/// Encode une phrase (liste de mots) terminée par un mot vide.
Uint8List encodeSentence(List<String> words) {
  final out = BytesBuilder();
  for (final w in words) {
    final bytes = utf8.encode(w);
    out.add(encodeLength(bytes.length));
    out.add(bytes);
  }
  out.addByte(0);
  return out.toBytes();
}

/// File d'octets alimentée par le socket, lue de façon asynchrone.
class ByteQueue {
  Uint8List _buf = Uint8List(0);
  int _pos = 0;
  bool _closed = false;
  Object? _error;
  Completer<void>? _waiter;

  int get available => _buf.length - _pos;

  void add(List<int> data) {
    if (data.isEmpty) return;
    final rest = available;
    final next = Uint8List(rest + data.length);
    next.setRange(0, rest, _buf, _pos);
    next.setRange(rest, next.length, data);
    _buf = next;
    _pos = 0;
    _wake();
  }

  void close() {
    _closed = true;
    _wake();
  }

  void fail(Object error) {
    _error = error;
    _closed = true;
    _wake();
  }

  void _wake() {
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<Uint8List> read(int n) async {
    while (available < n) {
      if (_closed) {
        throw _error ?? RouterOsException('Connexion fermée par le routeur.');
      }
      final w = Completer<void>();
      _waiter = w;
      await w.future;
    }
    final out = Uint8List.fromList(_buf.sublist(_pos, _pos + n));
    _pos += n;
    return out;
  }
}

/// Lecture des mots et phrases de l'API.
class ApiReader {
  ApiReader(this._queue);
  final ByteQueue _queue;

  Future<int> readLength() async {
    final first = (await _queue.read(1))[0];
    if (first < 0x80) return first;
    if ((first & 0xC0) == 0x80) {
      final b = await _queue.read(1);
      return ((first & 0x3F) << 8) | b[0];
    }
    if ((first & 0xE0) == 0xC0) {
      final b = await _queue.read(2);
      return ((first & 0x1F) << 16) | (b[0] << 8) | b[1];
    }
    if ((first & 0xF0) == 0xE0) {
      final b = await _queue.read(3);
      return ((first & 0x0F) << 24) | (b[0] << 16) | (b[1] << 8) | b[2];
    }
    if (first == 0xF0) {
      final b = await _queue.read(4);
      return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
    }
    throw RouterOsException('Réponse invalide du routeur.');
  }

  /// Lit une phrase complète (jusqu'au mot vide).
  Future<List<String>> readSentence() async {
    final words = <String>[];
    while (true) {
      final len = await readLength();
      if (len == 0) break;
      final bytes = await _queue.read(len);
      words.add(utf8.decode(bytes, allowMalformed: true));
    }
    return words;
  }
}

Map<String, String> parseAttributes(List<String> words) {
  final m = <String, String>{};
  for (final w in words.skip(1)) {
    if (!w.startsWith('=')) continue;
    final i = w.indexOf('=', 1);
    if (i > 0) {
      m[w.substring(1, i)] = w.substring(i + 1);
    } else {
      m[w.substring(1)] = '';
    }
  }
  return m;
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// Client de l'API RouterOS (port 8728, ou 8729 en TLS).
///
/// Les commandes sont exécutées l'une après l'autre. Si la connexion est
/// tombée (veille du téléphone, VPN coupé…), elle est rouverte avant la
/// commande suivante.
class RouterOsClient {
  RouterOsClient({
    required this.host,
    required this.port,
    required this.useSsl,
    required this.username,
    required this.password,
    this.connectTimeout = const Duration(seconds: 10),
    this.commandTimeout = const Duration(seconds: 30),
  });

  final String host;
  final int port;
  final bool useSsl;
  final String username;
  final String password;
  final Duration connectTimeout;
  final Duration commandTimeout;

  Socket? _socket;
  ByteQueue _queue = ByteQueue();
  ApiReader _reader = ApiReader(ByteQueue());
  bool _dead = true;
  Future<void> _lock = Future<void>.value();

  /// Ouvre la connexion et s'identifie.
  Future<void> connect() => _open();

  Future<void> _open() async {
    _teardown();
    final Socket s;
    if (useSsl) {
      s = await SecureSocket.connect(
        host,
        port,
        timeout: connectTimeout,
        onBadCertificate: (_) => true, // certificats auto-signés des routeurs
      );
    } else {
      s = await Socket.connect(host, port, timeout: connectTimeout);
    }
    s.setOption(SocketOption.tcpNoDelay, true);
    final q = ByteQueue();
    _socket = s;
    _queue = q;
    _reader = ApiReader(q);
    _dead = false;
    s.listen(
      q.add,
      onError: (Object e) {
        q.fail(e);
        if (identical(_queue, q)) _dead = true;
      },
      onDone: () {
        q.close();
        if (identical(_queue, q)) _dead = true;
      },
      cancelOnError: true,
    );
    try {
      await _login();
    } catch (_) {
      _teardown();
      rethrow;
    }
  }

  Future<void> _login() async {
    try {
      final first = await _doExec(['/login', '=name=$username', '=password=$password']);
      final challenge = first.done['ret'];
      if (challenge != null && challenge.isNotEmpty) {
        // RouterOS < 6.43 : authentification par défi MD5.
        final bytes = <int>[0, ...utf8.encode(password), ..._hexDecode(challenge)];
        final digest = md5.convert(bytes).toString();
        await _doExec(['/login', '=name=$username', '=response=00$digest']);
      }
    } on RouterOsException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('cannot log in') || m.contains('invalid user')) {
        throw RouterOsException('Identifiant ou mot de passe incorrect.');
      }
      rethrow;
    }
  }

  static List<int> _hexDecode(String hex) {
    final out = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  void _teardown() {
    _dead = true;
    _socket?.destroy();
    _socket = null;
  }

  void close() => _teardown();

  /// Exécute une commande et renvoie les lignes `!re`.
  Future<List<Map<String, String>>> run(List<String> words) async =>
      (await exec(words)).rows;

  /// Exécute une commande et renvoie la réponse complète.
  Future<ApiReply> exec(List<String> words) {
    final completer = Completer<ApiReply>();
    final previous = _lock;
    _lock = completer.future.then<void>((_) {}, onError: (Object _) {});
    previous.then((_) async {
      try {
        if (_dead) await _open();
        final reply = await _doExec(words).timeout(commandTimeout, onTimeout: () {
          _teardown();
          throw TimeoutException('Le routeur ne répond pas.');
        });
        completer.complete(reply);
      } catch (e, s) {
        if (e is! RouterOsException) _teardown();
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  Future<ApiReply> _doExec(List<String> words) async {
    final socket = _socket;
    if (socket == null) {
      throw RouterOsException('Non connecté au routeur.');
    }
    socket.add(encodeSentence(words));
    await socket.flush();

    final rows = <Map<String, String>>[];
    String? trap;
    while (true) {
      final sentence = await _reader.readSentence();
      if (sentence.isEmpty) continue;
      switch (sentence.first) {
        case '!re':
          rows.add(parseAttributes(sentence));
          break;
        case '!done':
          if (trap != null) throw RouterOsException(trap);
          return ApiReply(rows, parseAttributes(sentence));
        case '!trap':
          trap = parseAttributes(sentence)['message'] ?? 'Erreur du routeur.';
          break;
        case '!fatal':
          throw RouterOsException(
              sentence.length > 1 ? sentence[1] : 'Erreur fatale du routeur.');
      }
    }
  }
}
