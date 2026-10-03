// ignore_for_file: avoid_print
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/game_state.dart';

/// 网络服务：基于 Socket.IO 实现五子棋在线对战功能。
/// 负责 WebSocket 连接管理、房间操作、走棋同步、聊天和异常处理。
/// 无直接 UI 状态变更，通过回调通知上层。
///
/// 事件名与服务端（server/index.js）严格对齐：
///   服务器 → 客户端: registered / roomCreated / roomJoined / opponentJoined /
///                    playerReady / gameStarted / move / gameOver / chatMessage /
///                    undoAsk / undoAnswer / undone / undoCancelled /
///                    errorMsg / opponentLeft / opponentDisconnected
///   客户端 → 服务器: register / createRoom / joinRoom / startGame /
///                    makeMove / resign / chat / undoRequest / undoReply / leaveRoom
class NetworkService {
  // ========== 状态字段 ==========

  /// 当前所在房间 ID
  String? roomId;

  /// 当前玩家名称
  String? playerName;

  /// 我方执子颜色
  Player myColor = Player.black;

  /// 内部连接状态标志（兼容 getter 只读限制）
  bool _isConnected = false;

  /// 连接是否已建立
  bool get isConnected => _socket?.connected ?? _isConnected;

  /// 是否已创建或加入房间
  bool get hasRoom => roomId != null;

  /// 是否轮到我方落子（由服务器 gameStarted / move 事件驱动更新）
  bool yourTurn = false;

  /// 对弈方颜色（由服务器告知）
  Player? opponentColor;

  /// 对方玩家名称
  String? opponentName;

  /// 页面回调尚未挂上时收到的聊天消息缓存（[消息, 发送者]），
  /// 对局页挂载后由 [flushPendingChat] 补发，避免导航窗口内漏消息
  final List<List<String>> _pendingChat = [];

  // ========== 回调函数 ==========

  /// 收到通用消息时触发
  void Function(String message)? onMessage;

  /// 连接成功时触发
  void Function()? onConnected;

  /// 连接断开时触发
  void Function()? onDisconnected;

  /// 对手准备就绪时触发，附带其执子颜色
  void Function(Player color)? onOpponentJoined;

  /// 对手落子时触发
  /// [pos] 落子坐标, [player] 落子方
  void Function(Position pos, Player player)? onOpponentMove;

  /// 对局正式开始时触发（双方都就绪后）
  void Function()? onGameStarted;

  /// 对局结束时触发。[winner] 为获胜方颜色，null 表示平局
  void Function(Player? winner)? onGameEnded;

  /// 收到聊天消息时触发
  /// [message] 消息内容, [sender] 发送者名称
  void Function(String message, String sender)? onChatMessage;

  /// 对手请求悔棋时触发（被请求方收到），[name] 为请求者昵称
  void Function(String name)? onUndoAsk;

  /// 悔棋请求的答复（请求方收到）。accept=false 时 [reason] 说明原因
  void Function(bool accept, String reason)? onUndoAnswer;

  /// 悔棋生效时触发（双方都收到）：
  /// [removed] 被撤销的落点, [nextPlayer] 接下来该谁落子
  void Function(List<Position> removed, Player nextPlayer)? onUndone;

  /// 对手的悔棋请求被取消（请求者离开/掉线）时触发（被请求方收到）
  void Function()? onUndoCancelled;

  /// 收到错误信息时触发
  /// [error] 错误文本, [sender] 来源标识
  void Function(String error, String sender)? onError;

  /// 重新连接成功时触发
  void Function(int attempts)? onReconnected;

  /// 重新连接失败时触发
  void Function(dynamic error)? onReconnectError;

  // ========== Socket 实例与服务端地址 ==========

  io.Socket? _socket;
  final String serverUrl; // 服务端根 URL，如 http://192.168.1.100
  final String hostIp; // 本机 IP / 公网 IP

  /// 创建网络服务实例
  /// [serverUrl] WebSocket 服务端地址，默认本地回环地址
  /// [hostIp] 局域网中可访问的主机 IP
  NetworkService({
    this.serverUrl = 'http://localhost',
    this.hostIp = '127.0.0.1',
  });

  // ---------- 连接管理 ----------

  /// 连接到 WebSocket 服务端
  /// 设置所有事件监听器，等待服务器响应
  Future<bool> connect() async {
    try {
      if (isConnected) return true;

      // hostIp 支持 "IP" 或 "IP:端口" 两种写法；不写端口时默认 3000
      final url = serverUrlOverride ??
          (hostIp.contains(':') ? 'http://$hostIp' : 'http://$hostIp:3000');

      _socket = io.io(
        url,
        <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': true,
          'timeout': 10000, // 10秒超时
        },
      );

      // 配置全局事件监听器
      _setupListeners();

      // 等待首次连接确认
      await Future.delayed(const Duration(milliseconds: 2000));
      if (isConnected) {
        // 自动注册
        _socket?.emit('register', {'name': playerName ?? '玩家'});
      }

      return isConnected;
    } catch (e) {
      _onErrorInternal('连接失败: $e', 'Network');
      return false;
    }
  }

  /// 可选的完整服务器地址覆盖（如 wss://example.com:443），为空时使用 hostIp
  String? serverUrlOverride;

  // ---------- 事件监听 ----------

  /// 设置所有 Socket.IO 事件监听
  void _setupListeners() {
    if (_socket == null) return;

    // 连接成功
    _socket!.on('connect', (_) {
      _isConnected = true;
      // 断线重连后服务端按新的 socketId 识别玩家，
      // 必须重发注册，否则后续建房/落子指令会被服务器静默丢弃
      _socket?.emit('register', {'name': playerName ?? '玩家'});
      onConnected?.call();
    });

    // 连接断开
    _socket!.on('disconnect', (_) {
      _isConnected = false;
      onDisconnected?.call();
    });

    // 注册成功（服务器回传规范化的玩家名）
    _socket!.on('registered', (data) {
      try {
        final name = data['name']?.toString();
        if (name != null && name.isNotEmpty) playerName = name;
      } catch (_) {
        // 忽略解析失败，不影响后续流程
      }
    });

    // 房间创建成功（用于导航到对战场面）
    _socket!.on('roomCreated', (data) {
      try {
        final rid = data['roomId']?.toString() ?? '';
        if (rid.isNotEmpty) {
          roomId = rid;
          final colorStr =
              data['yourColor']?.toString().toLowerCase() ?? 'black';
          myColor = colorStr == 'white' ? Player.white : Player.black;
        }
        yourTurn = false;
        onMessage?.call('房间创建成功');
      } catch (e) {
        _onErrorInternal('解析房间创建数据失败: $e', 'Socket');
      }
    });

    // 加入房间成功（服务器向加入者定向发送）
    _socket!.on('roomJoined', (data) {
      try {
        final rid = data['roomId']?.toString() ?? '';
        if (rid.isNotEmpty) {
          roomId = rid;
          final colorStr =
              data['yourColor']?.toString().toLowerCase() ?? 'black';
          myColor = colorStr == 'white' ? Player.white : Player.black;
        }
        opponentName = data['opponentName']?.toString() ?? '对手';
        opponentColor = myColor.opponent();
        yourTurn = false;
        onMessage?.call('已加入房间');
      } catch (e) {
        _onErrorInternal('解析房间加入数据失败: $e', 'Socket');
      }
    });

    // 对手加入房间（服务器向房间内既有玩家定向发送）
    _socket!.on('opponentJoined', (data) {
      try {
        final name = data['name']?.toString() ?? '对手';
        final colorStr = data['color']?.toString().toLowerCase() ?? 'white';
        opponentName = name;
        opponentColor = colorStr == 'black' ? Player.black : Player.white;
        onMessage?.call('$name 加入了房间');
      } catch (e) {
        _onErrorInternal('解析对手加入数据失败: $e', 'Socket');
      }
    });

    // 对手准备就绪（服务器向另一方定向发送）
    _socket!.on('playerReady', (data) {
      try {
        final name = data['name']?.toString() ?? '对手';
        final colorStr = data['color']?.toString().toLowerCase() ?? 'white';
        opponentName = name;
        opponentColor = colorStr == 'black' ? Player.black : Player.white;
        onOpponentJoined?.call(opponentColor!);
      } catch (e) {
        _onErrorInternal('解析对手准备数据失败: $e', 'Socket');
      }
    });

    // 对局开始（服务器分别向两名玩家定向发送，yourColor/yourTurn 因人而异）
    _socket!.on('gameStarted', (data) {
      try {
        final colorStr = data['yourColor']?.toString().toLowerCase() ?? 'black';
        myColor = colorStr == 'white' ? Player.white : Player.black;
        opponentColor = myColor.opponent();
        yourTurn = data['yourTurn'] == true;
        onGameStarted?.call();
        onMessage?.call(yourTurn ? '对局开始，轮到你落子' : '对局开始，等待对手...');
      } catch (e) {
        _onErrorInternal('解析对局开始数据失败: $e', 'Socket');
      }
    });

    // 走棋广播（服务器向房间两人广播，含自己回合的回声）
    _socket!.on('move', (data) {
      try {
        final row = data['row'] as int;
        final col = data['col'] as int;
        final colorStr =
            data['playerColor']?.toString().toLowerCase() ?? 'black';
        final mover = colorStr == 'white' ? Player.white : Player.black;
        final nextStr = data['nextPlayer']?.toString().toLowerCase() ?? 'black';
        yourTurn =
            (nextStr == 'white' ? Player.white : Player.black) == myColor;

        // 忽略自己落子的回声，只把对手的走棋上报 UI
        if (mover != myColor) {
          onOpponentMove?.call(Position(row: row, col: col), mover);
        }
      } catch (e) {
        _onErrorInternal('解析走棋数据失败: $e', 'Socket');
      }
    });

    // 对局结束（五连 / 满盘 / 投降 / 掉线，winnerColor 为 null 表示平局）
    _socket!.on('gameOver', (data) {
      yourTurn = false;
      try {
        final wc = data['winnerColor']?.toString().toLowerCase();
        final reason = data['reason']?.toString() ?? '';
        Player? winner;
        if (wc == 'black') {
          winner = Player.black;
        } else if (wc == 'white') {
          winner = Player.white;
        }
        onGameEnded?.call(winner);
        switch (reason) {
          case 'resign':
            onMessage?.call('对手投降');
            break;
          case 'disconnected':
          case 'left':
            onMessage?.call('对手离开了对局');
            break;
          default:
            break;
        }
      } catch (e) {
        _onErrorInternal('解析对局结束数据失败: $e', 'Socket');
      }
    });

    // 收到聊天消息
    _socket!.on('chatMessage', (data) {
      try {
        final message = data['message']?.toString() ?? '';
        final sender = data['sender']?.toString() ?? '未知';
        final cb = onChatMessage;
        if (cb != null) {
          cb(message, sender);
        } else {
          // 大厅→对局导航窗口内页面尚未挂载：先缓存，挂载后 flushPendingChat 补发
          _pendingChat.add([message, sender]);
        }
      } catch (e) {
        _onErrorInternal('解析聊天消息失败: $e', 'Socket');
      }
    });

    // 对手请求悔棋（定向发给被请求方）
    _socket!.on('undoAsk', (data) {
      try {
        final name = data['name']?.toString() ?? '对手';
        onUndoAsk?.call(name);
      } catch (e) {
        _onErrorInternal('解析悔棋请求失败: $e', 'Socket');
      }
    });

    // 悔棋答复（请求方收到）
    _socket!.on('undoAnswer', (data) {
      try {
        final accept = data['accept'] == true;
        final reason = data['reason']?.toString() ?? '';
        onUndoAnswer?.call(accept, reason);
      } catch (e) {
        _onErrorInternal('解析悔棋答复失败: $e', 'Socket');
      }
    });

    // 悔棋生效（房间双方都收到）
    _socket!.on('undone', (data) {
      try {
        final removed = <Position>[];
        final list = data['removed'];
        if (list is List) {
          for (final m in list) {
            final row = m['row'];
            final col = m['col'];
            if (row is int && col is int) {
              removed.add(Position(row: row, col: col));
            }
          }
        }
        final nextStr = data['nextPlayer']?.toString().toLowerCase() ?? 'black';
        onUndone?.call(
            removed, nextStr == 'white' ? Player.white : Player.black);
      } catch (e) {
        _onErrorInternal('解析悔棋结果失败: $e', 'Socket');
      }
    });

    // 悔棋请求被取消（请求方离开/掉线）
    _socket!.on('undoCancelled', (_) => onUndoCancelled?.call());

    // 对手离开房间（等待阶段）
    _socket!.on('opponentLeft', (data) {
      try {
        final name = data['name']?.toString() ?? '对手';
        opponentName = null;
        opponentColor = null;
        onMessage?.call('$name 已离开房间');
      } catch (_) {
        onMessage?.call('对手离开了房间');
      }
    });

    // 对手掉线（等待阶段）
    _socket!.on('opponentDisconnected', (data) {
      try {
        final name = data['name']?.toString() ?? '对手';
        onMessage?.call('$name 已断开连接');
      } catch (_) {
        onMessage?.call('对手已断开连接');
      }
    });

    // 错误通知
    _socket!.on('errorMsg', (data) {
      try {
        final errorMsg = data['message']?.toString() ?? data.toString();
        final sender = data['sender']?.toString() ?? 'Server';
        _onErrorInternal(errorMsg, sender);
      } catch (_) {
        _onErrorInternal(data.toString(), 'Server');
      }
    });

    // 重连成功
    _socket!.on('reconnect', (data) {
      _isConnected = true;
      final attempts = data is int ? data : 0;
      onReconnected?.call(attempts);
      onMessage?.call('已重新连接到服务器');
    });

    // 重连失败
    _socket!.on('reconnectError', (data) {
      final error = data ?? '未知的重连错误';
      onReconnectError?.call(error);
    });
  }

  /// 断开与 WebSocket 服务端的连接
  /// 清理所有监听器和内部状态
  Future<void> disconnect() async {
    try {
      // 断开连接，清理所有事件监听由 disconnect() 自动处理
      _socket?.disconnect();
      _socket?.dispose();
      _socket = null;
    } catch (e) {
      // 忽略断开过程中的错误
    } finally {
      _isConnected = false;
      resetRoomState();
    }
  }

  /// 清空本地房间状态（不关闭连接）
  void resetRoomState() {
    roomId = null;
    opponentColor = null;
    opponentName = null;
    yourTurn = false;
  }

  // ---------- 房间操作 ----------

  /// 创建一个新游戏房间
  /// [name] 房间名称
  /// [playerColor] 选择的执子颜色
  /// 成功时通过回调通知，失败时触发 onError 回调
  void createRoom(String name, {Player playerColor = Player.black}) {
    try {
      if (!isConnected) {
        _onErrorInternal('未连接到服务器', 'Network');
        return;
      }
      setMyColor(playerColor);
      _socket!.emit('createRoom', <String, dynamic>{
        'roomName': name,
        'playerColor': playerColor == Player.black ? 'black' : 'white',
      });
    } catch (e) {
      _onErrorInternal('创建房间失败: $e', 'Network');
    }
  }

  /// 加入一个已有房间
  /// [roomId] 房间唯一标识符（也支持房间名称）
  void joinRoom(String roomId) {
    try {
      if (!isConnected) {
        _onErrorInternal('未连接到服务器', 'Network');
        return;
      }
      _socket!.emit('joinRoom', <String, dynamic>{
        'roomId': roomId,
        'playerName': playerName ?? '无名棋手',
      });
    } catch (e) {
      _onErrorInternal('加入房间失败: $e', 'Network');
    }
  }

  /// 向服务器请求开始对局（双方都准备就绪后自动开始）
  void startGame() {
    try {
      if (!isConnected || roomId == null) {
        _onErrorInternal('无法开始对局：未连接或不在房间内', 'Network');
        return;
      }
      _socket!.emit('startGame', {'roomId': roomId});
    } catch (e) {
      _onErrorInternal('请求开始对局失败: $e', 'Network');
    }
  }

  /// 申请离开当前房间（仅清除本地房间状态，保留连接）
  void leaveRoom() {
    try {
      if (!isConnected || roomId == null) return;
      _socket!.emit('leaveRoom', {'roomId': roomId});
      resetRoomState();
    } catch (e) {
      _onErrorInternal('离开房间失败: $e', 'Network');
    }
  }

  // ---------- 对局操作 ----------

  /// 向服务器发送走棋指令
  /// [row] 行坐标（从 0 开始）
  /// [col] 列坐标（从 0 开始）
  void makeMove(int row, int col) {
    try {
      if (!isConnected || roomId == null) {
        _onErrorInternal('无法落子：未连接或不在房间内', 'Network');
        return;
      }
      yourTurn = false;
      _socket!.emit('makeMove', <String, dynamic>{
        'roomId': roomId,
        'row': row,
        'col': col,
        'playerColor': myColor == Player.black ? 'black' : 'white',
      });
    } catch (e) {
      yourTurn = true; // 发送失败，恢复回合以便重试
      _onErrorInternal('落子发送失败: $e', 'Network');
    }
  }

  /// 发送投降信号给服务器和对局对手
  void resign() {
    try {
      if (!isConnected || roomId == null) return;
      _socket!.emit('resign', {'roomId': roomId});
    } catch (e) {
      _onErrorInternal('投降发送失败: $e', 'Network');
    }
  }

  // ---------- 聊天功能 ----------

  /// 发送聊天消息到当前房间
  /// [message] 聊天内容
  void sendChat(String message) {
    try {
      if (!isConnected || roomId == null) {
        _onErrorInternal('无法发送消息：未连接或不在房间内', 'Network');
        return;
      }
      if (message.trim().isEmpty) return;
      _socket!.emit('chat', <String, dynamic>{
        'roomId': roomId,
        'message': message.trim(),
        'sender': playerName ?? '未知用户',
      });
    } catch (e) {
      _onErrorInternal('发送消息失败: $e', 'Network');
    }
  }

  // ---------- 悔棋功能（需对方同意） ----------

  /// 向对手发送悔棋请求
  void requestUndo() {
    try {
      if (!isConnected || roomId == null) {
        _onErrorInternal('无法悔棋：未连接或不在房间内', 'Network');
        return;
      }
      _socket!.emit('undoRequest', <String, dynamic>{'roomId': roomId});
    } catch (e) {
      _onErrorInternal('悔棋请求发送失败: $e', 'Network');
    }
  }

  /// 答复对手的悔棋请求（被请求方调用）
  void replyUndo(bool accept) {
    try {
      if (!isConnected || roomId == null) return;
      _socket!.emit('undoReply', <String, dynamic>{
        'roomId': roomId,
        'accept': accept,
      });
    } catch (e) {
      _onErrorInternal('悔棋答复发送失败: $e', 'Network');
    }
  }

  // ---------- Setter / Getter 辅助方法 ----------

  /// 设置我方执子颜色
  void setMyColor(Player color) {
    myColor = color;
  }

  /// 设置当前玩家显示名称
  void setName(String name) {
    playerName = name.trim().isEmpty ? '棋手' : name.trim();
  }

  // ---------- 内部错误处理 ----------

  /// 内部错误回调统一入口
  /// 将错误转发至 onError 回调；如果未注册回调则输出日志
  void _onErrorInternal(String error, String sender) {
    print('[NetworkService Error][from=$sender]: $error');
    onError?.call(error, sender);
    onMessage?.call('错误: $error');
  }

  // ---------- 销毁资源 ----------

  /// 对局页挂载并挂好回调后调用：补发导航窗口内缓存的聊天消息
  void flushPendingChat() {
    final cb = onChatMessage;
    if (cb == null || _pendingChat.isEmpty) return;
    final batch = List<List<String>>.from(_pendingChat);
    _pendingChat.clear();
    for (final m in batch) {
      cb(m[0], m[1]);
    }
  }

  /// 解除本实例对上层的所有回调引用（页面弹出时调用，防止旧页面被回调唤醒）。
  /// 不会关闭 socket，连接由持有方（大厅）继续管理。
  void clearCallbacks() {
    onMessage = null;
    onConnected = null;
    onDisconnected = null;
    onOpponentJoined = null;
    onOpponentMove = null;
    onGameStarted = null;
    onGameEnded = null;
    onChatMessage = null;
    onUndoAsk = null;
    onUndoAnswer = null;
    onUndone = null;
    onUndoCancelled = null;
    onError = null;
    onReconnected = null;
    onReconnectError = null;
    // 离开房间后缓存队列一并作废，防止旧房消息串入新房
    _pendingChat.clear();
  }

  /// 彻底销毁网络连接并清理资源
  /// 在页面关闭或应用退出时调用
  void dispose() {
    disconnect();
    // 清空所有回调引用以防止内存泄漏
    clearCallbacks();
  }
}
