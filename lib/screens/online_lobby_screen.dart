import 'package:flutter/material.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/models/theme_model.dart';
import 'package:gomuku/services/network_service.dart';
import 'package:gomuku/services/storage_service.dart';
import 'package:go_router/go_router.dart';

/// 在线匹配大厅 —— 连接服务器、创建/加入房间。
class OnlineLobbyScreen extends StatefulWidget {
  const OnlineLobbyScreen({super.key});

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  NetworkService? _network;
  String _connectionStatus =
      'disconnected'; // connected | disconnected | connecting | error
  String _savedIp = '192.168.1.1';

  final _roomNameController = TextEditingController();
  final _roomIdController = TextEditingController();
  Player _selectedColor = Player.black;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSavedIp();
  }

  Future<void> _loadSavedIp() async {
    await StorageService.init();
    setState(() {
      _savedIp = StorageService().serverIp;
      _connectionStatus = 'disconnected';
    });
  }

  bool _navigating = false;

  /// 状态栏展示用：兼容 "IP" 与 "IP:端口" 两种输入，缺省端口按 3000 显示
  String get _serverDisplay =>
      _savedIp.contains(':') ? _savedIp : '$_savedIp:3000';

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
            backgroundColor: Colors.redAccent,
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
          backgroundColor: Colors.orange,
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
    _network!.createRoom(name, playerColor: _selectedColor);

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
          backgroundColor: Colors.orange,
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
    final palette = ThemePalette.all[StorageService().themeIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text('在线对弈'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_ios_rounded, size: 20),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: palette.primaryColor,
          labelColor: palette.primaryColor,
          unselectedLabelColor: palette.secondaryColor.withValues(alpha: 0.5),
          tabs: const [
            Tab(text: '创建房间'),
            Tab(text: '加入房间'),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [palette.bgColor, palette.boardBgColor],
          ),
        ),
        child: Column(
          children: [
            // ========== 连接状态栏 ==========
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _connectionStatus == 'connected'
                      ? Colors.green.shade400
                      : _connectionStatus == 'error'
                          ? Colors.red.shade400
                          : palette.primaryColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // Status dot
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _connectionStatus == 'connected'
                          ? Colors.green
                          : _connectionStatus == 'error'
                              ? Colors.red
                              : Colors.grey,
                      boxShadow: _connectionStatus == 'connected'
                          ? [
                              BoxShadow(
                                color: Colors.green.withValues(alpha: 0.4),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getStatusText(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _getTextColor(),
                          ),
                        ),
                        Text(
                          '服务器: $_serverDisplay',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.secondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Connect/Disconnect button
                  FilledButton(
                    onPressed: _connectionStatus == 'connecting'
                        ? null
                        : _toggleConnection,
                    style: FilledButton.styleFrom(
                      backgroundColor: _connectionStatus == 'connected'
                          ? Colors.red.shade100
                          : null,
                    ),
                    child: _connectionStatus == 'connecting'
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                palette.primaryColor,
                              ),
                            ),
                          )
                        : Text(
                            _connectionStatus == 'connected' ? '断开' : '连接',
                            style: TextStyle(
                              color: _connectionStatus == 'connected'
                                  ? Colors.red.shade700
                                  : palette.primaryColor,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // ========== IP输入区 ==========
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: InputDecoration(
                  labelText: '服务器地址（IP 或 IP:端口）',
                  hintText: '例如：192.168.1.100 或 1.2.3.4:3001',
                  prefixIcon: Icon(Icons.network_ping_outlined, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                ),
                // url 键盘带 "." 和 ":"，纯数字键盘无法输入端口号
                keyboardType: TextInputType.url,
                onChanged: (value) =>
                    _savedIp = value.isNotEmpty ? value : '192.168.1.1',
                onSubmitted: (_) => _toggleConnection(),
              ),
            ),

            const SizedBox(height: 12),

            // ========== Tab内容区 ==========
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // -- Tab 1: 创建房间 --
                  _buildCreateTab(palette),
                  // -- Tab 2: 加入房间 --
                  _buildJoinTab(palette),
                ],
              ),
            ),

            // ========== 底部规则说明 ==========
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: palette.bgColor.withValues(alpha: 0.5),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '游戏规则',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: palette.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '双方轮流落子，先将五子连成一线者获胜。黑方先行，无贴目。棋盘为标准15×15。',
                    style:
                        TextStyle(fontSize: 12, color: palette.secondaryColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '温馨提示：确保与对手在同一局域网内，或已正确配置公网地址和端口映射。',
                    style:
                        TextStyle(fontSize: 12, color: palette.secondaryColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Tab builders ----------

  Widget _buildCreateTab(ThemePalette palette) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              fillColor: Colors.white.withValues(alpha: 0.1),
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
              icon: Icon(Icons.add_circle_outline, color: Colors.white),
              label: Text(
                '创建房间',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
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
              fillColor: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          const SizedBox(height: 20),
          // Join button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _joinRoom,
              icon: Icon(Icons.login_rounded, color: Colors.white),
              label: Text(
                '加入房间',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: palette.secondaryColor,
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
              color: Colors.white.withValues(alpha: 0.08),
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

  Color _getTextColor() {
    switch (_connectionStatus) {
      case 'connected':
        return Colors.green.shade600;
      case 'error':
        return Colors.red.shade600;
      case 'connecting':
        return Colors.orange.shade600;
      default:
        return Colors.grey.shade600;
    }
  }
}
