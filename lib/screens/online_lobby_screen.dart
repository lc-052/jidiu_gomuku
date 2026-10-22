import 'package:flutter/material.dart';
import '../widgets/section_card.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/models/theme_model.dart';
import 'package:gomuku/services/network_service.dart';
import 'package:gomuku/services/storage_service.dart';
import 'package:go_router/go_router.dart';
import '../services/server_address.dart';
import '../models/game_kind.dart';

/// 在线匹配大厅 —— 连接服务器、创建/加入房间。
class OnlineLobbyScreen extends StatefulWidget {
  final GameKind kind;
  const OnlineLobbyScreen({super.key, this.kind = GameKind.gomoku});

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  NetworkService? _network;
  String _connectionStatus =
      'disconnected'; // connected | disconnected | connecting | error
  String _savedIp = StorageService().serverIp;

  final _roomNameController = TextEditingController();
  final _roomIdController = TextEditingController();
  Player _selectedColor = Player.black;
  late int _boardSize = widget.kind == GameKind.go ? 9 : 15;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedIp();
  }

  Future<void> _loadSavedIp() async {
    await StorageService.init();
    if (!mounted) return;
    setState(() {
      _savedIp = StorageService().serverIp;
      _connectionStatus = 'disconnected';
    });
  }

  bool _navigating = false;

  /// 状态栏展示用：兼容 "IP" 与 "IP:端口" 两种输入，缺省端口按 3000 显示
  String get _serverDisplay {
    try {
      return parseServerAddress(_savedIp).toString();
    } on FormatException {
      return _savedIp;
    }
  }

  void _setNetworkCallbacks() {
    if (_network == null) return;
    _network!.onConnected = () {
      if (!mounted) return;
      setState(() => _connectionStatus = 'connected');
    };
    _network!.onDisconnected = () {
      if (!mounted) return;
      setState(() => _connectionStatus = 'disconnected');
    };
    _network!.onError = (error, sender) {
      if (!mounted) return;
      setState(() => _connectionStatus = 'error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('错误 [$sender]: $error')),
      );
    };
    // 房间创建成功 → 跳转到对战场面
    _network!.onMessage = (msg) {
      if (_navigating) return;
      // 如果是房间创建/加入成功的消息，自动跳转
      if (msg.contains('房间创建成功') || msg.contains('已加入房间')) {
        _navigating = true;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          if (_network?.roomId == null) {
            // 未进入房间（异常早退）：复位标志，允许下一次成功消息再触发跳转
            _navigating = false;
            return;
          }
          GoRouter.of(context).pushNamed('online-game', extra: {
            'network': _network,
            'roomId': _network!.roomId!,
            'playerColor':
                _network!.myColor == Player.black ? 'black' : 'white',
          }).then((_) {
            // 从对战页返回后，重新拿回连接回调，便于下一局
            _navigating = false;
            if (mounted) _setNetworkCallbacks();
          });
        });
      }
    };
  }

  Future<void> _toggleConnection() async {
    if (_connectionStatus == 'connected') {
      _network?.disconnect();
      setState(() => _connectionStatus = 'disconnected');
    } else {
      setState(() => _connectionStatus = 'connecting');
      // 重连前释放旧实例，避免遗留死连接
      _network?.dispose();
      _network = NetworkService(hostIp: _savedIp);
      _network!.expectedKind = widget.kind;
      _setNetworkCallbacks();
      final success = await _network!.connect();
      if (!mounted) return;
      setState(() => _connectionStatus = success ? 'connected' : 'error');
      if (success) {
        // 记住服务器地址，下次进入大厅自动回填
        await StorageService().saveServerIp(_savedIp);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接失败，请检查服务器地址和网络连接。'),
          ),
        );
      }
    }
  }

  void _createRoom() {
    if (_network == null || _connectionStatus != 'connected') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先连接到服务器！'),
        ),
      );
      return;
    }

    final name = _roomNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('房间名称不能为空！')),
      );
      return;
    }
    if (name.length > 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('房间名称不能超过20个字符！')),
      );
      return;
    }

    // 从对战页返回后回调可能被清空，创建前重新挂接
    _setNetworkCallbacks();
    // 注意：不要把房间名当玩家昵称 setName —— 服务器注册名以
    // registered 事件为准，本地覆盖会使聊天回声过滤
    // （sender == playerName）失效，导致自己的消息重复显示
    _network!.createRoom(name,
        playerColor: _selectedColor, kind: widget.kind, size: _boardSize);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在创建房间 "$name" ...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _joinRoom() {
    if (_network == null || _connectionStatus != 'connected') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先连接到服务器！'),
        ),
      );
      return;
    }

    final roomId = _roomIdController.text.trim();
    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('房间码不能为空！')),
      );
      return;
    }
    if (roomId.length > 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('房间码不能超过20个字符！')),
      );
      return;
    }

    // 从对战页返回后回调可能被清空，加入前重新挂接
    _setNetworkCallbacks();
    _network!.joinRoom(roomId);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在加入房间 "$roomId" ...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _roomNameController.dispose();
    _roomIdController.dispose();
    _network?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ThemePalette.resolve(context, StorageService().themeIndex);
    return Scaffold(
      appBar: AppBar(title: Text('在线棋室 · ${widget.kind.label}')),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          SectionCard(
              title: '连接棋室',
              subtitle: _getStatusText(),
              trailing: Icon(_connectionStatus == 'connected'
                  ? Icons.wifi_rounded
                  : Icons.wifi_off_rounded),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      initialValue: _savedIp,
                      key: ValueKey(_savedIp.isEmpty),
                      decoration: const InputDecoration(
                          labelText: '服务器地址',
                          hintText: '公网IP:端口 或 https://域名',
                          prefixIcon: Icon(Icons.dns_outlined)),
                      keyboardType: TextInputType.url,
                      onChanged: (v) => _savedIp = v,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.tonalIcon(
                              onPressed: _connectionStatus == 'connecting'
                                  ? null
                                  : _toggleConnection,
                              icon:
                                  const Icon(Icons.power_settings_new_rounded),
                              label: Text(_connectionStatus == 'connecting'
                                  ? '正在连接…'
                                  : _connectionStatus == 'connected'
                                      ? '断开连接'
                                      : '连接服务器')),
                          Text('当前：$_serverDisplay'),
                        ]),
                  ])),
          const SizedBox(height: 16),
          Card(
              child: TabBar(
                  controller: _tabController,
                  onTap: (_) => setState(() {}),
                  tabs: const [Tab(text: '创建房间'), Tab(text: '加入房间')])),
          const SizedBox(height: 16),
          if (_tabController.index == 0)
            _buildCreateTab(palette)
          else
            _buildJoinTab(palette),
          const SizedBox(height: 16),
          SectionCard(
              title: '联机约定',
              child: Text(widget.kind == GameKind.go
                  ? '围棋支持 9 / 13 / 19 路，白贴 7.5 目。双停后共同标记死子，双方确认才结算；修改死子后需要重新确认。'
                  : '五子棋使用 15 × 15 棋盘。连接同一服务器后，创建房间并分享房间码，双方准备即可开始。')),
        ]),
      )),
    );
  }

  // ---------- Tab builders ----------

  Widget _buildCreateTab(ThemePalette palette) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.kind == GameKind.go) ...[
            const Text('棋盘大小'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final size in [9, 13, 19])
                ChoiceChip(
                    label: Text('$size × $size'),
                    selected: _boardSize == size,
                    onSelected: (_) => setState(() => _boardSize = size))
            ]),
            const SizedBox(height: 20),
          ],
          // Room name
          Text(
            '房间名称',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: palette.textColor,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _roomNameController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: '请输入房间名称（最多20字）',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              counterText: '${_roomNameController.text.length}/20',
            ),
            maxLength: 20,
          ),
          const SizedBox(height: 20),
          // Color choice
          Text(
            '选择执子颜色',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: palette.textColor,
            ),
          ),
          const SizedBox(height: 8),
          RadioGroup<Player>(
            groupValue: _selectedColor,
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selectedColor = v);
            },
            child: Row(
              children: [
                Expanded(
                  child: RadioListTile<Player>(
                    title: Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.black,
                        ),
                        const SizedBox(width: 8),
                        const Text('黑方'),
                      ],
                    ),
                    subtitle:
                        const Text('(先手)', style: TextStyle(fontSize: 11)),
                    value: Player.black,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                Expanded(
                  child: RadioListTile<Player>(
                    title: Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.circle,
                              size: 14, color: Colors.black26),
                        ),
                        const SizedBox(width: 8),
                        const Text('白方'),
                      ],
                    ),
                    subtitle:
                        const Text('(后手)', style: TextStyle(fontSize: 11)),
                    value: Player.white,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Create button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _createRoom,
              icon: const Icon(Icons.add_circle_outline),
              label: Text(
                '创建房间',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: palette.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '房间容量：1-2 人',
              style: TextStyle(
                fontSize: 12,
                color: palette.secondaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinTab(ThemePalette palette) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '房间码 / 名称',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: palette.textColor,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _roomIdController,
            decoration: InputDecoration(
              hintText: '请输入对方提供的 6 位数字房间码',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 20),
          // Join button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _joinRoom,
              icon: const Icon(Icons.login_rounded),
              label: Text(
                '加入房间',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: palette.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Mock room list placeholder
          Text(
            '当前可用房间',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: palette.textColor,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: palette.primaryColor.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.room_outlined,
                  size: 48,
                  color: palette.secondaryColor.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 8),
                Text(
                  '暂无房间',
                  style: TextStyle(
                    fontSize: 14,
                    color: palette.secondaryColor,
                  ),
                ),
                Text(
                  '创建房间后可把 6 位房间码发给好友加入',
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.secondaryColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Helpers ----------

  String _getStatusText() {
    switch (_connectionStatus) {
      case 'connected':
        return '已连接';
      case 'connecting':
        return '连接中...';
      case 'error':
        return '连接失败';
      default:
        return '未连接';
    }
  }
}
