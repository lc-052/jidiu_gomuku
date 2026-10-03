import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gomuku/main.dart';
import 'package:gomuku/models/game_state.dart';
import 'package:gomuku/models/theme_model.dart';
import 'package:gomuku/services/storage_service.dart';

/// 设置界面 —— 主题、难度、反馈、偏好等全局配置。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _themeIndex;
  late int _difficultyIndex;
  late bool _soundEnabled;
  late bool _vibrationEnabled;
  late Player _preferredColor;
  bool _showLastMove = true;
  late StorageService _storage;

  // ========== Lifecycle ==========

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _storage = StorageService();
    setState(() {
      _themeIndex = _storage.themeIndex;
      _difficultyIndex = _storage.difficultyIndex;
      _soundEnabled = _storage.soundEnabled;
      _vibrationEnabled = _storage.vibrationEnabled;
      _preferredColor = _storage.preferredColor;
    });
  }

  // ========== Save Helpers ==========

  Future<void> _saveSettings() async {
    await _storage.saveThemeIndex(_themeIndex);
    await _storage.saveDifficultyIndex(_difficultyIndex);
    if (!mounted) return;
    // 同步全局主题通知器，让首页 / 对战页立即换肤
    context.read<ThemeNotifier>().setThemeIndex(_themeIndex);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('设置已保存'), duration: Duration(seconds: 1)),
    );
  }

  // ========== UI ==========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('游戏设置'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
        ),
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section 1 — 主题选择
            _buildSectionTitle('选择主题'),
            const SizedBox(height: 8),
            _buildThemeSelector(),
            const Divider(height: 32),

            // Section 2 — AI 难度（仅人机对战有效）
            _buildSectionTitle('AI 难度'),
            const SizedBox(height: 8),
            _buildDifficultySelector(),
            const Divider(height: 32),

            // Section 3 — 反馈设置
            _buildSectionTitle('反馈设置'),
            const SizedBox(height: 8),
            _buildFeedbackSettings(),
            const Divider(height: 32),

            // Section 4 — 游戏偏好
            _buildSectionTitle('游戏偏好'),
            const SizedBox(height: 8),
            _buildGamePreferences(),
            const Divider(height: 32),

            // Section 5 — 关于
            _buildAboutSection(),
          ],
        ),
      ),
    );
  }

  // ---------- Builders ----------

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
    );
  }

  Widget _buildThemeSelector() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: List.generate(ThemePalette.all.length, (index) {
        final p = ThemePalette.all[index];
        final selected = _themeIndex == index;
        return GestureDetector(
          onTap: () => setState(() => _themeIndex = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.primaryColor,
                        border: Border.all(
                          color: selected ? p.primaryColor : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                    color:
                                        p.primaryColor.withValues(alpha: 0.4),
                                    blurRadius: 12)
                              ]
                            : null,
                      ),
                    ),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [p.primaryColor, p.secondaryColor],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(p.name,
                    style: TextStyle(
                        fontSize: 11,
                        color: selected ? p.primaryColor : Colors.grey)),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildDifficultySelector() {
    final items = const [
      ('easy', '简单', '轻度攻击，防守为主。适合初学者。'),
      ('medium', '中等', '均衡攻防，有一定策略。适合进阶玩家。'),
      ('hard', '困难', '强力进攻，Alpha-Beta 剪枝搜索。高手挑战！'),
    ];
    return RadioGroup<int>(
      groupValue: _difficultyIndex,
      onChanged: (v) {
        if (v == null) return;
        setState(() => _difficultyIndex = v);
        _storage.saveDifficultyIndex(v);
      },
      child: Column(
        children: List.generate(items.length, (i) {
          final label = items[i].$2;
          final desc = items[i].$3;
          return RadioListTile<int>(
            title:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(width: 8),
                Chip(
                  label: Text(label, style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: _chipColor(i),
                ),
              ]),
              Text(desc,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ]),
            value: i,
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          );
        }),
      ),
    );
  }

  Color _chipColor(int index) {
    const colors = [Colors.green, Colors.orange, Colors.red];
    return colors[index];
  }

  Widget _buildFeedbackSettings() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('音效反馈'),
          subtitle: const Text('落子时播放音效'),
          value: _soundEnabled,
          onChanged: (v) => setState(() {
            _soundEnabled = v;
            _storage.saveSoundEnabled(v);
          }),
          secondary: const Icon(Icons.volume_up_outlined),
        ),
        SwitchListTile(
          title: const Text('震动反馈'),
          subtitle: const Text('落子时手机震动提示'),
          value: _vibrationEnabled,
          onChanged: (v) => setState(() {
            _vibrationEnabled = v;
            _storage.saveVibrationEnabled(v);
          }),
          secondary: const Icon(Icons.vibration_outlined),
        ),
      ],
    );
  }

  Widget _buildGamePreferences() {
    return Column(
      children: [
        RadioGroup<Player>(
          groupValue: _preferredColor,
          onChanged: (v) {
            if (v == null) return;
            setState(() => _preferredColor = v);
            _storage.savePreferredColor(v == Player.black ? 'black' : 'white');
          },
          child: Column(
            children: [
              RadioListTile<Player>(
                title: const Text('默认执色：黑方（先手）'),
                subtitle: const Text('新游戏中默认执黑先行'),
                value: Player.black,
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              RadioListTile<Player>(
                title: const Text('默认执色：白方（后手）'),
                subtitle: const Text('新游戏中默认执白后行'),
                value: Player.white,
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('显示最后一步标记'),
          subtitle: const Text('在棋盘上高亮最近一次落子位置'),
          value: _showLastMove,
          onChanged: (v) => setState(() => _showLastMove = v),
          secondary: const Icon(Icons.flag_outlined),
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    final p = ThemePalette.all[_themeIndex];
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Icon(Icons.sports_golf_rounded, size: 40, color: p.primaryColor),
          const SizedBox(height: 12),
          Text('寄丢五子棋',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: p.primaryColor,
                  letterSpacing: 2)),
          const SizedBox(height: 4),
          Text('v1.0.0',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          Text('开源免费 · 欢乐博弈',
              style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: p.secondaryColor)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _confirmReset(),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('重置所有设置'),
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red)),
          ),
        ]),
      ),
    );
  }

  void _confirmReset() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置设置'),
        content: const Text('确定要恢复出厂设置吗？所有自定义配置将被清除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              if (!mounted) return;
              Navigator.of(ctx).pop();
              await _storage.clearAll();
              setState(() {
                _themeIndex = 0;
                _difficultyIndex = 1;
                _soundEnabled = true;
                _vibrationEnabled = true;
                _preferredColor = Player.black;
              });
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('设置已重置为默认值')));
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
  }
}
