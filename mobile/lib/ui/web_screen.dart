import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_services.dart';
import '../core/models.dart';

const _pageHosts = ['instagram.com', 'cdninstagram.com', 'facebook.com', 'fbcdn.net', 'youtube.com', 'youtu.be', 'ytimg.com', 'google.com', 'gstatic.com', 'googlevideo.com', 'googleusercontent.com'];

/// Whether the in-app page may go to [url]: https only, on a host of Instagram, YouTube or the login and consent pages they use.
bool allowedPage(String url) {
  if (url == 'about:blank') return true;
  final u = Uri.tryParse(url);
  if (u == null || u.scheme != 'https') return false;
  final h = u.host.toLowerCase();
  return _pageHosts.any((d) => h == d || h.endsWith('.$d'));
}

/// A reel's link opened inside the app, so you can watch the original without leaving it.
class WebScreen extends StatefulWidget {
  final AppServices services;
  final String url;
  final String title;
  const WebScreen(this.services, {required this.url, required this.title, super.key});

  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {
  late final WebViewController _web;
  int _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        // Pages may move around Instagram and YouTube (login, consent), but only over https and only to Instagram, YouTube, Facebook (Instagram's login) and Google (consent) hosts.
        onNavigationRequest: (r) => allowedPage(r.url) ? NavigationDecision.navigate : NavigationDecision.prevent,
        onProgress: (p) => setState(() => _progress = p),
        onPageStarted: (_) => setState(() => _failed = false),
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? false) setState(() => _failed = true);
        },
      ))
      ..loadRequest(Uri.parse(isReelLink(widget.url) ? widget.url : 'about:blank'));
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _web.canGoBack()) {
            await _web.goBack();
          } else if (context.mounted) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _web.reload),
              IconButton(
                tooltip: 'Open in the Instagram or YouTube app',
                icon: const Icon(Icons.open_in_new),
                onPressed: isReelLink(widget.url) ? () => widget.services.bridge.openUrl(widget.url) : null,
              ),
            ],
            bottom: _progress < 100
                ? PreferredSize(preferredSize: const Size.fromHeight(3), child: LinearProgressIndicator(value: _progress / 100, minHeight: 3))
                : null,
          ),
          body: _failed
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('The page could not load. Check your internet connection.', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _web.reload, child: const Text('Try again')),
                    ]),
                  ),
                )
              : WebViewWidget(controller: _web),
        ),
      );
}
