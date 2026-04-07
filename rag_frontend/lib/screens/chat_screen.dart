import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/persona_model.dart';
import '../models/session_model.dart';
import '../providers/chat_provider.dart';
import '../providers/persona_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';
import '../widgets/file_upload_widget.dart';

class ChatScreen extends StatefulWidget {
  final Persona persona;

  const ChatScreen({
    Key? key,
    required this.persona,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatProvider _chatProvider;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  bool _showFileUpload = false;

  @override
  void initState() {
    super.initState();
    _chatProvider = context.read<ChatProvider>();
    Future.microtask(() {
      _chatProvider.loadSessions(widget.persona.id);
      _chatProvider.loadChatHistory(widget.persona.id);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() async {
    final message = _messageController.text.trimRight();
    if (message.isEmpty) return;

    _messageController.clear();

    await _chatProvider.sendMessage(widget.persona.id, message);
    _scrollToBottom();
  }

  void _showFileManager() async {
    final apiService = context.read<PersonaProvider>().apiService;
    List<Map<String, dynamic>> files = [];

    try {
      files = await apiService.getFiles(widget.persona.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('파일 목록 조회 실패: $e')),
        );
      }
      return;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.3,
              maxChildSize: 0.8,
              expand: false,
              builder: (ctx, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_open, color: Color(0xFF6366F1)),
                          const SizedBox(width: 8),
                          Text(
                            '업로드된 파일 (${files.length})',
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (files.isEmpty)
                      const Expanded(
                        child: Center(child: Text('업로드된 파일이 없습니다')),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: files.length,
                          itemBuilder: (ctx, index) {
                            final file = files[index];
                            return ListTile(
                              leading: Icon(
                                _getFileIconByType(file['file_type'] ?? ''),
                                color: const Color(0xFF6366F1),
                              ),
                              title: Text(
                                file['filename'] ?? 'Unknown',
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(file['file_type'] ?? ''),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: ctx,
                                    builder: (dCtx) => AlertDialog(
                                      title: const Text('파일 삭제'),
                                      content: Text("'${file['filename']}' 파일을 삭제하시겠습니까?\n관련 벡터 데이터도 함께 삭제됩니다."),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dCtx, false),
                                          child: const Text('취소'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(dCtx, true),
                                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                                          child: const Text('삭제'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    final provider = context.read<PersonaProvider>();
                                    final ok = await provider.deleteFileFromPersona(
                                      widget.persona.id,
                                      file['id'],
                                    );
                                    if (ok) {
                                      setSheetState(() {
                                        files.removeAt(index);
                                      });
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text("'${file['filename']}' 삭제 완료")),
                                        );
                                      }
                                    }
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  IconData _getFileIconByType(String fileType) {
    switch (fileType) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'text':
        return Icons.description;
      case 'audio':
        return Icons.audio_file;
      case 'document':
        return Icons.article;
      default:
        return Icons.insert_drive_file;
    }
  }

  void _createNewSession() async {
    await _chatProvider.createNewSession(widget.persona.id);
  }

  void _showRenameDialog(ChatSession session) {
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Session'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Session title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _chatProvider.renameSession(
                    widget.persona.id, session.id, controller.text);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(ChatSession session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session'),
        content: Text('Delete "${session.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _chatProvider.deleteSession(widget.persona.id, session.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
              ),
              child: Row(
                children: [
                  const Icon(Icons.chat, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Sessions',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    onPressed: () {
                      _createNewSession();
                      Navigator.pop(context);
                    },
                    tooltip: 'New Chat',
                  ),
                ],
              ),
            ),
            // Session list
            Expanded(
              child: Consumer<ChatProvider>(
                builder: (context, chatProvider, _) {
                  if (chatProvider.sessions.isEmpty) {
                    return const Center(
                      child: Text('No sessions yet',
                          style: TextStyle(color: Colors.grey)),
                    );
                  }
                  return ListView.builder(
                    itemCount: chatProvider.sessions.length,
                    itemBuilder: (context, index) {
                      final session = chatProvider.sessions[index];
                      final isActive =
                          session.id == chatProvider.currentSessionId;
                      return ListTile(
                        leading: Icon(
                          Icons.chat_bubble_outline,
                          color: isActive
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                          size: 20,
                        ),
                        title: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          '${session.messageCount} messages  •  ${session.formattedDate}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: isActive,
                        selectedTileColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.08),
                        trailing: PopupMenuButton<String>(
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'rename', child: Text('Rename')),
                            const PopupMenuItem(
                                value: 'delete', child: Text('Delete')),
                          ],
                          onSelected: (value) {
                            if (value == 'rename') {
                              _showRenameDialog(session);
                            } else if (value == 'delete') {
                              _showDeleteConfirm(session);
                            }
                          },
                          icon: const Icon(Icons.more_vert, size: 18),
                        ),
                        onTap: () {
                          chatProvider.switchSession(
                              widget.persona.id, session.id);
                          Navigator.pop(context);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '홈으로',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.persona.name),
            Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                final session = chatProvider.sessions
                    .where((s) => s.id == chatProvider.currentSessionId)
                    .firstOrNull;
                return Text(
                  session?.title ?? widget.persona.description,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.normal),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New Chat',
            onPressed: _createNewSession,
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: () {
                  setState(() => _showFileUpload = !_showFileUpload);
                },
                child: const Row(
                  children: [
                    Icon(Icons.upload_file),
                    SizedBox(width: 8),
                    Text('Upload File'),
                  ],
                ),
              ),
              PopupMenuItem(
                onTap: () => _showFileManager(),
                child: const Row(
                  children: [
                    Icon(Icons.folder_open),
                    SizedBox(width: 8),
                    Text('Manage Files'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      drawer: _buildSessionDrawer(),
      body: Column(
        children: [
          // File upload widget
          if (_showFileUpload)
            FileUploadWidget(
              personaId: widget.persona.id,
              onSuccess: () {
                setState(() => _showFileUpload = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File uploaded successfully')),
                );
              },
            ),

          // Messages area
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, _) {
                if (chatProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (chatProvider.messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: AppTheme.spacing16),
                        Text(
                          'No messages yet',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppTheme.spacing8),
                        Text(
                          'Start a conversation with your persona',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppTheme.spacing16),
                  itemCount: chatProvider.messages.length,
                  itemBuilder: (context, index) {
                    final message = chatProvider.messages[index];
                    // 마지막 AI 메시지가 비어있고 상태 메시지가 있으면 버블 안에 표시
                    final isLastEmpty = index == chatProvider.messages.length - 1 &&
                        !message.isUser &&
                        message.content.isEmpty &&
                        chatProvider.statusMessage != null;
                    return MessageBubble(
                      message: message,
                      statusMessage: isLastEmpty ? chatProvider.statusMessage : null,
                    );
                  },
                );
              },
            ),
          ),

          // Input area
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter &&
                          !HardwareKeyboard.instance.isShiftPressed) {
                        _sendMessage();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _messageController,
                      focusNode: _inputFocusNode,
                      decoration: InputDecoration(
                        hintText: 'Type your message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radius12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing12,
                          vertical: AppTheme.spacing12,
                        ),
                      ),
                      minLines: 1,
                      maxLines: 5,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.spacing12),
                Consumer<ChatProvider>(
                  builder: (context, chatProvider, _) {
                    return FloatingActionButton(
                      mini: true,
                      onPressed: chatProvider.isStreaming ? null : _sendMessage,
                      child: const Icon(Icons.send),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
