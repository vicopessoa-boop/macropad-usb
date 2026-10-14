import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macropad_usb/models/claude_session.dart';
import 'package:macropad_usb/models/layer.dart';
import 'package:macropad_usb/models/macro_action.dart';
import 'package:macropad_usb/models/status_update.dart';
import 'package:macropad_usb/services/default_layers.dart';
import 'package:macropad_usb/services/macropad_connection.dart';
import 'package:macropad_usb/ui/macropad_screen.dart';

void main() {
  test('Layer.fromJson lê o formato do config.json do desktop', () {
    final layers = Layer.listFromJson(
      jsonDecode('''[
      {"id":"git","name":"Git","color":"#7CFF00","columns":4,"keys":[
        {"id":"btn_push","label":"Push","confirm":true,"color":"#FF6B00",
         "action":{"action_type":"EXEC_SHELL","payload":{"command":"git push"}}}
      ]}
    ]''') as List,
    );
    final k = layers.single.keys.single;
    expect(layers.single.columns, 4);
    expect(layers.single.color, const Color(0xFF7CFF00));
    expect(k.confirm, isTrue);
    expect(k.action.isShell, isTrue);
    expect(k.action.toMessage(buttonId: k.id, requestId: 'r1'), {
      'type': 'ACTION',
      'action_type': 'EXEC_SHELL',
      'button_id': 'btn_push',
      'request_id': 'r1',
      'payload': {'command': 'git push'},
    });
  });

  test('StatusUpdate.fromJson', () {
    final s = StatusUpdate.fromJson({
      'type': 'STATUS_UPDATE',
      'button_id': 'btn_docker_build',
      'status': 'SUCCESS',
      'color_hex': '#00FF66',
    })!;
    expect(s.status, KeyStatus.success);
    expect(s.color, const Color(0xFF00FF66));
    expect(StatusUpdate.fromJson({'status': 'SUCCESS'}), isNull);
  });

  test('conecta, recebe LAYOUT, envia ACTION e recebe STATUS_UPDATE', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<Map<String, dynamic>>();
    server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.add(
        jsonEncode({
          'type': 'LAYOUT',
          'layers': [
            {'id': 'x', 'name': 'X', 'keys': []},
          ],
        }),
      );
      ws.listen((data) {
        final msg = Map<String, dynamic>.from(jsonDecode(data as String) as Map);
        if (msg['type'] == 'ACTION') {
          received.complete(msg);
          ws.add(jsonEncode({'type': 'STATUS_UPDATE', 'button_id': msg['button_id'], 'status': 'RUNNING'}));
        }
      });
    });

    final conn = MacropadConnection(port: server.port)..start();
    final status = conn.statusUpdates.first;
    while (conn.phase != ConnectionPhase.connected) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(conn.sendAction('btn_a', MacroAction.combo(['ctrl', 'shift', 'p'])), isTrue);

    final msg = await received.future.timeout(const Duration(seconds: 2));
    expect(msg['action_type'], 'KEY_COMBO');
    expect(msg['payload'], {
      'keys': ['ctrl', 'shift', 'p'],
    });
    expect((await status.timeout(const Duration(seconds: 2))).status, KeyStatus.running);
    expect(conn.remoteLayers.value?.single.id, 'x');

    conn.dispose();
    await server.close(force: true);
  });

  testWidgets('renderiza as layers padrão e troca de perfil', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // Porta 1: nada escutando, o app fica em "Desconectado" sem travar o teste.
    final conn = MacropadConnection(port: 1);
    await tester.pumpWidget(MaterialApp(home: MacropadScreen(connection: conn)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Palette'), findsOneWidget);
    expect(find.text('Desconectado'), findsOneWidget);

    await tester.tap(find.text('2  ${defaultLayers[1].name}'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Docker Build'), findsOneWidget);

    // Tocar uma tecla desconectado mostra o aviso em vez de travar.
    await tester.tap(find.text('Pull'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Sem conexão'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    conn.dispose();
  });

  testWidgets('visor do Claude mostra o estado de cada sessão', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final conn = MacropadConnection(port: 1);
    await tester.pumpWidget(MaterialApp(home: MacropadScreen(connection: conn)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('CLAUDE CODE'), findsOneWidget);

    conn.claudeSessions.value = [
      ClaudeSession.fromJson({'id': 'a', 'project': 'zx-control-semana1', 'state': 'waiting', 'updated_ms': 2}),
      ClaudeSession.fromJson({'id': 'b', 'project': 'macropad-usb', 'state': 'done', 'updated_ms': 1}),
    ];
    await tester.pump(const Duration(milliseconds: 100));
    // Desconectado: o visor avisa em vez de mostrar estados possivelmente velhos.
    expect(find.text('Desktop desconectado'), findsOneWidget);

    await tester.tap(find.text('2  ${defaultLayers[1].name}'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('CLAUDE CODE'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    conn.dispose();
  });
}
