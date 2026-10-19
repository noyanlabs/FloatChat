import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

const String kWorkerUrl = 'https://floatchat.buoyantai.workers.dev/';

// ---------------------------------------------------------------------------
// Palette — pure black & white, modern through contrast and depth rather
// than color. Named by function, not hue, so the rest of the file reads the
// same regardless of the underlying values.
// ---------------------------------------------------------------------------
const Color kInk = Color(0xFF0A0A0A);        // near-black, primary surfaces/text
const Color kInkSoft = Color(0xFF262626);    // secondary dark (gradients, headers)
const Color kGraphite = Color(0xFF4A4A4A);   // muted text / secondary labels
const Color kSlate = Color(0xFF8A8A8A);      // tertiary text / placeholders
const Color kMist = Color(0xFFD8D8D8);       // dividers, subtle borders
const Color kFog = Color(0xFFF0F0F0);        // recessed fills (code chips, table header)
const Color kPaper = Color(0xFFFAFAFA);      // app background
const Color kWhite = Color(0xFFFFFFFF);      // card surfaces

/// Team roster — always visible beneath the header. In a monochrome system,
/// per-person distinction comes from a grayscale "weight" rather than hue:
/// leadership roles sit closer to black, supporting roles step lighter, so
/// the strip still reads as a hierarchy at a glance instead of a flat list.
class _TeamMember {
  final String name;
  final String role;
  final Color shade;
  const _TeamMember(this.name, this.role, this.shade);
}

const List<_TeamMember> kTeamRoster = [
  _TeamMember('Asjad Syed', 'Leader, Chief Architect', kInk),
  _TeamMember('Aradhya', 'Co-lead, Backend Engineer', kInkSoft),
  _TeamMember('Jairaj Shinde', 'Co-Architect', kInkSoft),
  _TeamMember('Mujtaba Khan', 'Frontend Engineer', kGraphite),
  _TeamMember('Daksh Agarwal', 'Demo & Pitch Lead', kGraphite),
  _TeamMember('Shagun Mishra', 'Storytelling Lead', kGraphite),
];

class ChatMessage {
  final String question;
  final String? answer;
  final String? sql;
  final List<dynamic>? rows;
  final String? error;
  final bool isLoading;

  ChatMessage({
    required this.question,
    this.answer,
    this.sql,
    this.rows,
    this.error,
    this.isLoading = false,
  });

  ChatMessage copyWith({
    String? answer,
    String? sql,
    List<dynamic>? rows,
    String? error,
    bool? isLoading,
  }) {
    return ChatMessage(
      question: question,
      answer: answer ?? this.answer,
      sql: sql ?? this.sql,
      rows: rows ?? this.rows,
      error: error ?? this.error,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class FloatChatScreen extends StatefulWidget {
  const FloatChatScreen({super.key});
  @override
  State<FloatChatScreen> createState() => _FloatChatScreenState();
}

class _FloatChatScreenState extends State<FloatChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isSending = false;

  Future<void> _sendQuestion() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _isSending) return;

    setState(() {
      _messages.add(ChatMessage(question: question, isLoading: true));
      _isSending = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final response = await http
          .post(
        Uri.parse(kWorkerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'question': question}),
      )
          .timeout(const Duration(seconds: 30));

      final index = _messages.length - 1;
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['error'] == null) {
        setState(() {
          _messages[index] = _messages[index].copyWith(
            answer: data['answer'] as String?,
            sql: data['sql'] as String?,
            rows: data['rows'] as List<dynamic>?,
            isLoading: false,
          );
        });
      } else {
        setState(() {
          _messages[index] = _messages[index].copyWith(
            error: (data['detail'] ?? data['error'] ?? 'Unknown error').toString(),
            sql: data['sql'] as String?,
            isLoading: false,
          );
        });
      }
    } catch (e) {
      final index = _messages.length - 1;
      setState(() {
        _messages[index] = _messages[index].copyWith(
          error: 'Network error: could not reach FloatChat. $e',
          isLoading: false,
        );
      });
    } finally {
      setState(() => _isSending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 700; // desktop/tablet breakpoint
    // Cap content width on large screens so the chat doesn't stretch edge to edge
    final contentMaxWidth = isWide ? 820.0 : double.infinity;

    return Scaffold(
      backgroundColor: kPaper,
      appBar: _FloatChatHeader(isWide: isWide),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMaxWidth),
                  child: _messages.isEmpty
                      ? _buildEmptyState(isWide)
                      : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 0 : 12,
                      vertical: 16,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _ChatBubble(
                        message: _messages[index],
                        isWide: isWide,
                      );
                    },
                  ),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: _buildInputBar(isWide),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isWide) {
    final examples = [
      'What is the average temperature in this dataset?',
      'Show me the deepest pressure reading recorded',
      'How many good-quality salinity readings do we have?',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Icon(Icons.water_drop_outlined, size: isWide ? 64 : 48, color: kMist),
          const SizedBox(height: 16),
          Text(
            'Ask about ARGO ocean data',
            style: TextStyle(
              fontSize: isWide ? 22 : 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Natural language questions about temperature, salinity,\npressure, and float locations.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: examples.map((e) {
              return ActionChip(
                label: Text(e, style: const TextStyle(fontSize: 13)),
                backgroundColor: Colors.white,
                side: const BorderSide(color: kMist),
                onPressed: () {
                  _controller.text = e;
                  _sendQuestion();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isWide) {
    return Container(
      padding: EdgeInsets.fromLTRB(isWide ? 0 : 12, 8, isWide ? 0 : 12, isWide ? 20 : 12),
      child: Material(
        elevation: 1,
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendQuestion(),
                  decoration: const InputDecoration(
                    hintText: 'Ask a question about the ocean data…',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isSending ? kMist : kInk,
                ),
                child: IconButton(
                  onPressed: _isSending ? null : _sendQuestion,
                  icon: _isSending
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Icon(Icons.arrow_upward_rounded),
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header: logo banner + always-visible team roster
// ---------------------------------------------------------------------------

class _FloatChatHeader extends StatelessWidget implements PreferredSizeWidget {
  final bool isWide;
  const _FloatChatHeader({required this.isWide});

  static const double _bannerHeight = 68;
  static const double _teamStripHeight = 60;

  @override
  Size get preferredSize => Size.fromHeight(_bannerHeight + _teamStripHeight);

  @override
  Widget build(BuildContext context) {
    return PreferredSize(
      preferredSize: preferredSize,
      child: Material(
        elevation: 3,
        shadowColor: Colors.black26,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SafeArea(
              bottom: false,
              child: Container(
                height: _bannerHeight,
                padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [kInk, kInkSoft],
                  ),
                ),
                child: Row(
                  children: [
                    _LogoMark(size: isWide ? 42 : 36),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'FloatChat',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: isWide ? 22 : 19,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Text(
                          'Conversational ARGO Ocean Data',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
                            fontSize: isWide ? 12.5 : 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (isWide)
                      Container(
                        width: 1,
                        height: 26,
                        color: Colors.white.withOpacity(0.18),
                      ),
                  ],
                ),
              ),
            ),
            Container(
              height: _teamStripHeight,
              color: kWhite,
              child: Row(
                children: [
                  Container(
                    height: _teamStripHeight,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: kMist)),
                    ),
                    child: const Icon(Icons.groups_rounded, size: 18, color: kSlate),
                  ),
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: kTeamRoster.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) => _TeamChip(member: kTeamRoster[index]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders the team's logo image if present at [assetPath]; falls back to a
/// simple vector mark so the header still looks intentional if the asset
/// hasn't been added to pubspec.yaml yet.
class _LogoMark extends StatelessWidget {
  final double size;
  const _LogoMark({required this.size});

  static const String assetPath = 'assets/logo.png';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // Asset not bundled yet — show a clean fallback mark instead of
            // a broken-image icon so the header never looks unfinished.
            return Container(
              color: kInk,
              alignment: Alignment.center,
              child: Icon(Icons.water_drop_rounded, color: Colors.white, size: size * 0.56),
            );
          },
        ),
      ),
    );
  }
}

class _TeamChip extends StatelessWidget {
  final _TeamMember member;
  const _TeamChip({required this.member});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kMist),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Grayscale weight dot in place of a hue — darker for leadership
          // roles, lighter for supporting roles.
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 7),
            decoration: BoxDecoration(shape: BoxShape.circle, color: member.shade),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                member.name,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kInk, height: 1.15),
              ),
              Text(
                member.role,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: kGraphite, height: 1.15),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isWide;

  const _ChatBubble({required this.message, required this.isWide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // User question — right aligned
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 500 : 280),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: kInk,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: kInk.withOpacity(0.16), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: Text(
                  message.question,
                  style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Assistant response — left aligned, full width available
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 780 : double.infinity),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kMist),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: _buildContent(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (message.isLoading) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Thinking…', style: TextStyle(color: Colors.black54)),
        ],
      );
    }

    if (message.error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  message.error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                ),
              ),
            ],
          ),
          if (message.sql != null) ...[
            const SizedBox(height: 8),
            _SqlBlock(sql: message.sql!),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MarkdownText(data: message.answer ?? ''),
        if (message.sql != null) ...[
          const SizedBox(height: 12),
          _SqlExpander(sql: message.sql!),
        ],
        if (message.rows != null && message.rows!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ResultChart(rows: message.rows!),
          const SizedBox(height: 12),
          _ResultTable(rows: message.rows!),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Markdown rendering
//
// The Cloudflare Worker's LLM answer sometimes returns light markdown
// (headers, **bold**, *italic*, `code`, lists). This is a small
// self-contained parser rather than a package dependency, because the
// requirement is specifically per-element COLOR styling — bold, italic,
// code, and headers each need a distinct look, which means building a
// custom TextSpan tree either way. Unmatched markers (an unclosed ** or a
// stray *) degrade to literal plain text instead of throwing or eating the
// rest of the line.
// ---------------------------------------------------------------------------

enum _MdSpanKind { plain, bold, italic, code }

class _MdSpan {
  final String text;
  final _MdSpanKind kind;
  _MdSpan(this.text, this.kind);
}

enum _MdBlockKind { paragraph, h1, h2, h3, bullet, numbered }

class _MdBlock {
  final _MdBlockKind kind;
  final List<_MdSpan> spans;
  final int? number;
  _MdBlock(this.kind, this.spans, {this.number});
}

List<_MdSpan> _parseInline(String line) {
  final spans = <_MdSpan>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isNotEmpty) {
      spans.add(_MdSpan(buffer.toString(), _MdSpanKind.plain));
      buffer.clear();
    }
  }

  int i = 0;
  while (i < line.length) {
    if (i + 1 < line.length && line[i] == '*' && line[i + 1] == '*') {
      final end = line.indexOf('**', i + 2);
      if (end != -1 && end > i + 2) {
        flush();
        spans.add(_MdSpan(line.substring(i + 2, end), _MdSpanKind.bold));
        i = end + 2;
        continue;
      }
    }
    if (line[i] == '`') {
      final end = line.indexOf('`', i + 1);
      if (end != -1 && end > i + 1) {
        flush();
        spans.add(_MdSpan(line.substring(i + 1, end), _MdSpanKind.code));
        i = end + 1;
        continue;
      }
    }
    if (line[i] == '*' && (i + 1 >= line.length || line[i + 1] != '*')) {
      final end = line.indexOf('*', i + 1);
      if (end != -1 && end > i + 1) {
        flush();
        spans.add(_MdSpan(line.substring(i + 1, end), _MdSpanKind.italic));
        i = end + 1;
        continue;
      }
    }
    buffer.write(line[i]);
    i++;
  }
  flush();
  return spans;
}

List<_MdBlock> _parseMarkdown(String text) {
  final lines = text.split('\n');
  final blocks = <_MdBlock>[];

  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;

    if (line.startsWith('### ')) {
      blocks.add(_MdBlock(_MdBlockKind.h3, _parseInline(line.substring(4))));
    } else if (line.startsWith('## ')) {
      blocks.add(_MdBlock(_MdBlockKind.h2, _parseInline(line.substring(3))));
    } else if (line.startsWith('# ')) {
      blocks.add(_MdBlock(_MdBlockKind.h1, _parseInline(line.substring(2))));
    } else if (line.trimLeft().startsWith('- ') || line.trimLeft().startsWith('* ')) {
      final content = line.trimLeft().substring(2);
      blocks.add(_MdBlock(_MdBlockKind.bullet, _parseInline(content)));
    } else {
      final numMatch = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(line.trimLeft());
      if (numMatch != null) {
        blocks.add(_MdBlock(
          _MdBlockKind.numbered,
          _parseInline(numMatch.group(2)!),
          number: int.parse(numMatch.group(1)!),
        ));
      } else {
        blocks.add(_MdBlock(_MdBlockKind.paragraph, _parseInline(line)));
      }
    }
  }
  return blocks;
}

/// Renders parsed markdown as a color-coded widget tree: bold text in the
/// brand deep-blue, italics in teal, inline code as a highlighted chip, and
/// each heading level in its own weight/color so the hierarchy is visible
/// at a glance rather than relying on size alone.
class _MarkdownText extends StatelessWidget {
  final String data;
  const _MarkdownText({required this.data});

  static const TextStyle _baseStyle = TextStyle(fontSize: 15, height: 1.5, color: Colors.black87);

  @override
  Widget build(BuildContext context) {
    final blocks = _parseMarkdown(data);
    if (blocks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map(_buildBlock).toList(),
    );
  }

  Widget _buildBlock(_MdBlock block) {
    switch (block.kind) {
      case _MdBlockKind.h1:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 2),
          child: _richText(block.spans, base: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: kInk, height: 1.3,
          )),
        );
      case _MdBlockKind.h2:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 2),
          child: _richText(block.spans, base: const TextStyle(
            fontSize: 17.5, fontWeight: FontWeight.w700, color: kInk, height: 1.3,
          )),
        );
      case _MdBlockKind.h3:
        return Padding(
          padding: const EdgeInsets.only(bottom: 4, top: 2),
          child: _richText(block.spans, base: const TextStyle(
            fontSize: 15.5, fontWeight: FontWeight.w600, color: kInkSoft, height: 1.3,
          )),
        );
      case _MdBlockKind.bullet:
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 7, right: 8),
                child: Icon(Icons.circle, size: 5, color: kInk),
              ),
              Expanded(child: _richText(block.spans, base: _baseStyle)),
            ],
          ),
        );
      case _MdBlockKind.numbered:
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${block.number}.',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk, height: 1.5),
                ),
              ),
              Expanded(child: _richText(block.spans, base: _baseStyle)),
            ],
          ),
        );
      case _MdBlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _richText(block.spans, base: _baseStyle),
        );
    }
  }

  Widget _richText(List<_MdSpan> spans, {required TextStyle base}) {
    return RichText(
      text: TextSpan(
        style: base,
        children: spans.map((s) {
          switch (s.kind) {
            case _MdSpanKind.bold:
              return TextSpan(
                text: s.text,
                style: const TextStyle(fontWeight: FontWeight.w800, color: kInk),
              );
            case _MdSpanKind.italic:
              return TextSpan(
                text: s.text,
                style: const TextStyle(fontStyle: FontStyle.italic, color: kGraphite),
              );
            case _MdSpanKind.code:
              return WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: kInk,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    s.text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: kWhite,
                    ),
                  ),
                ),
              );
            case _MdSpanKind.plain:
              return TextSpan(text: s.text);
          }
        }).toList(),
      ),
    );
  }
}

class _SqlBlock extends StatelessWidget {
  final String sql;
  const _SqlBlock({required this.sql});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kFog,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        sql,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: kInk),
      ),
    );
  }
}

class _SqlExpander extends StatefulWidget {
  final String sql;
  const _SqlExpander({required this.sql});

  @override
  State<_SqlExpander> createState() => _SqlExpanderState();
}

class _SqlExpanderState extends State<_SqlExpander> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: kInk,
              ),
              const SizedBox(width: 4),
              const Text(
                'Show generated SQL',
                style: TextStyle(color: kInk, fontSize: 13, fontWeight: FontWeight.w700, decoration: TextDecoration.underline, decorationColor: kMist),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          _SqlBlock(sql: widget.sql),
        ],
      ],
    );
  }
}

class _ResultTable extends StatelessWidget {
  final List<dynamic> rows;
  const _ResultTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final firstRow = rows.first as Map<String, dynamic>;
    final columns = firstRow.keys.toList();
    final displayRows = rows.take(20).toList(); // cap for readability

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: kMist),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(kFog),
          columns: columns
              .map((c) => DataColumn(
            label: Text(c, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          ))
              .toList(),
          rows: displayRows.map((r) {
            final row = r as Map<String, dynamic>;
            return DataRow(
              cells: columns
                  .map((c) => DataCell(Text('${row[c]}', style: const TextStyle(fontSize: 12.5))))
                  .toList(),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Charting
//
// SQL results are heterogeneous: an aggregate query returns one row with one
// number, a profile query returns many rows of pressure/temp/salinity, a
// trajectory query returns lat/lon pairs. Rather than assume a shape, this
// widget inspects the actual rows at runtime, finds numeric columns, and
// only renders a chart when there's an actual series worth plotting.
// ---------------------------------------------------------------------------

/// Columns that should never be treated as a plottable y-value even though
/// they may arrive as numbers (ids, QC flags, dimension indices).
const Set<String> _kNonMetricColumns = {
  'N_PROF',
  'N_LEVELS',
  'FLOAT_ID',
  'CYCLE_NUMBER',
  'TEMP_QC',
  'PRES_QC',
  'PSAL_QC',
  'ID',
};

/// Columns preferred as the x-axis when present, in priority order.
/// PRES/PRESSURE for depth-profiles, JULD/PROFILE_TIME for time series.
const List<String> _kPreferredXColumns = [
  'PRES',
  'PRESSURE',
  'JULD',
  'PROFILE_TIME',
  'CYCLE_NUMBER',
];

/// Attempts to parse a dynamic value (num, numeric string, or ISO date
/// string) into a plottable double. Returns null if it can't be treated
/// as a number — e.g. QC flag text, null, or a non-numeric string.
double? _asPlottableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    final asNum = num.tryParse(value);
    if (asNum != null) return asNum.toDouble();
    final asDate = DateTime.tryParse(value);
    if (asDate != null) {
      return asDate.millisecondsSinceEpoch.toDouble();
    }
  }
  return null;
}

class _ChartSeries {
  final String xColumn;
  final bool xIsDate;
  final Map<String, List<FlSpot>> yColumnToSpots;
  _ChartSeries({required this.xColumn, required this.xIsDate, required this.yColumnToSpots});
}

/// Inspects rows and builds one or more numeric series to plot.
/// Returns null when no sensible chart can be built (e.g. a single
/// aggregate row, or a result with no numeric columns at all).
_ChartSeries? _detectSeries(List<dynamic> rows) {
  if (rows.length < 2) return null; // one row (e.g. AVG()) isn't a chart

  final firstRow = rows.first as Map<String, dynamic>;
  final columns = firstRow.keys.toList();

  // Pick x-column: first preferred column that's actually present and numeric-parseable.
  String? xColumn;
  bool xIsDate = false;
  for (final candidate in _kPreferredXColumns) {
    final match = columns.firstWhere(
          (c) => c.toUpperCase() == candidate,
      orElse: () => '',
    );
    if (match.isEmpty) continue;
    final sample = _asPlottableDouble(firstRow[match]);
    if (sample != null) {
      xColumn = match;
      final rawSample = firstRow[match];
      xIsDate = rawSample is String && DateTime.tryParse(rawSample) != null && num.tryParse(rawSample) == null;
      break;
    }
  }
  // Fallback: use row index as x if nothing usable was found.
  xColumn ??= '';

  // Candidate y-columns: numeric, not in the exclusion list, not the x-column itself.
  final yColumns = <String>[];
  for (final col in columns) {
    if (col == xColumn) continue;
    if (_kNonMetricColumns.contains(col.toUpperCase())) continue;
    final sample = _asPlottableDouble(firstRow[col]);
    if (sample != null) yColumns.add(col);
  }

  if (yColumns.isEmpty) return null;

  // Cap to 3 series so the chart and legend stay readable.
  final limitedY = yColumns.take(3).toList();

  final result = <String, List<FlSpot>>{};
  for (final y in limitedY) {
    result[y] = [];
  }

  for (int i = 0; i < rows.length; i++) {
    final row = rows[i] as Map<String, dynamic>;
    final xVal = xColumn.isEmpty
        ? i.toDouble()
        : (_asPlottableDouble(row[xColumn]) ?? i.toDouble());
    for (final y in limitedY) {
      final yVal = _asPlottableDouble(row[y]);
      if (yVal != null) {
        result[y]!.add(FlSpot(xVal, yVal));
      }
    }
  }

  // If every series ended up empty (all null after all), there's nothing to plot.
  if (result.values.every((spots) => spots.isEmpty)) return null;

  return _ChartSeries(
    xColumn: xColumn.isEmpty ? 'Row' : xColumn,
    xIsDate: xIsDate,
    yColumnToSpots: result,
  );
}

/// Each entry pairs a grayscale shade with a line-style so up to three
/// series stay distinguishable without relying on hue — solid/dashed/dotted
/// carries the differentiation that color would otherwise provide.
class _SeriesStyle {
  final Color color;
  final List<int>? dashArray;
  const _SeriesStyle(this.color, this.dashArray);
}

const List<_SeriesStyle> _kSeriesStyles = [
  _SeriesStyle(kInk, null),           // solid
  _SeriesStyle(kGraphite, [6, 4]),    // dashed
  _SeriesStyle(kSlate, [1, 3]),       // dotted
];

/// Human-readable axis label with unit, keyed by the raw SQL column name
/// (case-insensitive). Falls back to a title-cased version of the column
/// name itself when it isn't a known oceanographic field.
String _axisLabel(String column) {
  const known = <String, String>{
    'PRES': 'Pressure (dbar)',
    'PRESSURE': 'Pressure (dbar)',
    'TEMP': 'Temperature (°C)',
    'TEMPERATURE': 'Temperature (°C)',
    'PSAL': 'Salinity (PSU)',
    'SALINITY': 'Salinity (PSU)',
    'JULD': 'Date',
    'PROFILE_TIME': 'Date',
    'LATITUDE': 'Latitude (°)',
    'LONGITUDE': 'Longitude (°)',
    'CYCLE_NUMBER': 'Cycle Number',
  };
  final hit = known[column.toUpperCase()];
  if (hit != null) return hit;
  if (column.isEmpty) return 'Row';
  // Fallback: turn SOME_COLUMN into "Some Column".
  return column
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

/// Draws a short line segment matching a series' actual dash pattern, so the
/// legend key visually matches the line on the chart instead of just a dot.
class _LegendSwatch extends StatelessWidget {
  final _SeriesStyle style;
  const _LegendSwatch({required this.style});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 10,
      child: CustomPaint(painter: _DashPainter(style)),
    );
  }
}

class _DashPainter extends CustomPainter {
  final _SeriesStyle style;
  _DashPainter(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = style.color
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;

    if (style.dashArray == null) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    final dash = style.dashArray![0].toDouble();
    final gap = style.dashArray!.length > 1 ? style.dashArray![1].toDouble() : dash;
    double x = 0;
    while (x < size.width) {
      final end = (x + dash).clamp(0, size.width).toDouble();
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) => oldDelegate.style != style;
}

class _ResultChart extends StatelessWidget {
  final List<dynamic> rows;
  const _ResultChart({required this.rows});

  @override
  Widget build(BuildContext context) {
    final series = _detectSeries(rows);
    if (series == null) return const SizedBox.shrink();

    // PRES is depth: oceanographic convention plots it increasing downward.
    final invertX = series.xColumn.toUpperCase() == 'PRES' || series.xColumn.toUpperCase() == 'PRESSURE';

    final entries = series.yColumnToSpots.entries.toList();

    // Compute bounds across all series with headroom so lines never sit
    // flush against the chart border — fl_chart's default auto-fit is tight
    // to the data, which reads as clipped rather than intentional.
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final e in entries) {
      for (final spot in e.value) {
        if (spot.x < minX) minX = spot.x;
        if (spot.x > maxX) maxX = spot.x;
        if (spot.y < minY) minY = spot.y;
        if (spot.y > maxY) maxY = spot.y;
      }
    }
    final hasBounds = minX.isFinite && maxX.isFinite && minY.isFinite && maxY.isFinite;
    final xSpan = hasBounds ? (maxX - minX) : 0.0;
    final ySpan = hasBounds ? (maxY - minY) : 0.0;
    // Guard against a zero-span axis (e.g. every y-value identical) which
    // would otherwise collapse the padding to nothing.
    final xPad = xSpan > 0 ? xSpan * 0.06 : 1.0;
    final yPad = ySpan > 0 ? ySpan * 0.12 : 1.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartHeight = constraints.maxWidth < 400 ? 220.0 : 280.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Legend — only shown when there's more than one series to disambiguate.
            if (entries.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: entries.asMap().entries.map((e) {
                    final style = _kSeriesStyles[e.key % _kSeriesStyles.length];
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LegendSwatch(style: style),
                        const SizedBox(width: 6),
                        Text(_axisLabel(e.value.key), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kInk)),
                      ],
                    );
                  }).toList(),
                ),
              ),
            SizedBox(
              height: chartHeight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 8),
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: null,
                      getDrawingHorizontalLine: (value) => FlLine(color: kFog, strokeWidth: 1),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        axisNameWidget: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _axisLabel(series.xColumn),
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.black87),
                          ),
                        ),
                        axisNameSize: 22,
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (value, meta) {
                            final label = series.xIsDate
                                ? _formatDateLabel(value)
                                : _formatNumericLabel(value);
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 44,
                          getTitlesWidget: (value, meta) => Text(
                            _formatNumericLabel(value),
                            style: const TextStyle(fontSize: 10, color: Colors.black54),
                          ),
                        ),
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: const Border(
                        bottom: BorderSide(color: kMist),
                        left: BorderSide(color: kMist),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => spots.map((s) {
                          return LineTooltipItem(
                            s.y.toStringAsFixed(2),
                            const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          );
                        }).toList(),
                      ),
                    ),
                    // NOTE: `invertX` (true when the x-axis is PRES/pressure) is
                    // computed above but was already unused in the original file —
                    // fl_chart's LineChartData requires minX < maxX, so flipping the
                    // depth-increases-downward convention needs either transforming
                    // the plotted x-values themselves or a manual reversed-axis
                    // painter, not a bounds swap. Left as pre-existing behavior
                    // rather than guessing at an unverified change.
                    minX: hasBounds ? minX - xPad : null,
                    maxX: hasBounds ? maxX + xPad : null,
                    minY: hasBounds ? minY - yPad : null,
                    maxY: hasBounds ? maxY + yPad : null,
                    lineBarsData: entries.asMap().entries.map((e) {
                      final style = _kSeriesStyles[e.key % _kSeriesStyles.length];
                      final spots = List<FlSpot>.from(e.value.value)..sort((a, b) => a.x.compareTo(b.x));
                      return LineChartBarData(
                        spots: spots,
                        isCurved: false,
                        color: style.color,
                        barWidth: 2.4,
                        dashArray: style.dashArray,
                        dotData: FlDotData(show: spots.length <= 30),
                        belowBarData: BarAreaData(show: false),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatNumericLabel(double value) {
    if (value.abs() >= 1000) return value.toStringAsFixed(0);
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  String _formatDateLabel(double millisSinceEpoch) {
    final date = DateTime.fromMillisecondsSinceEpoch(millisSinceEpoch.toInt());
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }
}