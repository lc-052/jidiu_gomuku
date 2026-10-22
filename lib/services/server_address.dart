/// Convert a user-facing IP/domain or root URL into a Socket.IO HTTP endpoint.
Uri parseServerAddress(String input) {
  final value = input.trim();
  if (value.isEmpty) throw const FormatException('请填写服务器地址');
  final explicitScheme = value.contains('://');
  var uri = Uri.parse(explicitScheme ? value : 'http://$value');
  if (!['http', 'https', 'ws', 'wss'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
    throw const FormatException('请填写 IP、域名:端口或完整的 HTTP/HTTPS 根地址');
  }
  final scheme = uri.scheme == 'wss'
      ? 'https'
      : uri.scheme == 'ws'
          ? 'http'
          : uri.scheme;
  uri = uri.replace(
      scheme: scheme,
      path: '',
      port: !explicitScheme && !uri.hasPort ? 3000 : null);
  return uri;
}
