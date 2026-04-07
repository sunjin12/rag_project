import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../providers/persona_provider.dart';
import '../theme/app_theme.dart';

class FileUploadWidget extends StatefulWidget {
  final String personaId;
  final VoidCallback onSuccess;

  const FileUploadWidget({
    Key? key,
    required this.personaId,
    required this.onSuccess,
  }) : super(key: key);

  @override
  State<FileUploadWidget> createState() => _FileUploadWidgetState();
}

class _FileUploadWidgetState extends State<FileUploadWidget> {
  List<PlatformFile> _selectedFiles = [];
  bool _isUploading = false;
  int _uploadedCount = 0;

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: ['pdf', 'txt', 'mp3', 'wav', 'm4a', 'ogg', 'flac', 'webm', 'doc', 'docx'],
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFiles.addAll(result.files);
      });
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  Future<void> _uploadFiles() async {
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('파일을 먼저 선택하세요')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadedCount = 0;
    });

    final provider = context.read<PersonaProvider>();
    int successCount = 0;
    int failCount = 0;

    for (final file in _selectedFiles) {
      if (file.path == null) continue;
      final ext = file.name.split('.').last;
      final fileType = _getFileType(ext);

      final success = await provider.uploadFileToPersona(
        widget.personaId,
        file.path!,
        fileType,
      );

      if (mounted) {
        setState(() => _uploadedCount++);
        if (success) {
          successCount++;
        } else {
          failCount++;
        }
      }
    }

    if (mounted) {
      setState(() {
        _selectedFiles.clear();
        _isUploading = false;
        _uploadedCount = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failCount == 0
                ? '$successCount개 파일 업로드 완료'
                : '$successCount개 성공, $failCount개 실패',
          ),
        ),
      );
      if (successCount > 0) widget.onSuccess();
    }
  }

  String _getFileType(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'pdf';
      case 'txt':
        return 'text';
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'ogg':
      case 'flac':
      case 'webm':
        return 'audio';
      case 'doc':
      case 'docx':
        return 'document';
      default:
        return 'unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(
            color: Colors.grey[300]!,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.upload_file, color: Color(0xFF6366F1)),
              const SizedBox(width: AppTheme.spacing8),
              Text(
                'Upload Files',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing12),
          if (_selectedFiles.isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _selectedFiles.length,
                itemBuilder: (context, index) {
                  final file = _selectedFiles[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing12,
                        vertical: AppTheme.spacing8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(AppTheme.radius8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _getFileIcon(file.name),
                            color: const Color(0xFF6366F1),
                            size: 20,
                          ),
                          const SizedBox(width: AppTheme.spacing8),
                          Expanded(
                            child: Text(
                              file.name,
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!_isUploading)
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              onPressed: () => _removeFile(index),
                              icon: const Icon(Icons.clear, size: 16),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_isUploading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: LinearProgressIndicator(
                  value: _selectedFiles.isEmpty
                      ? 0
                      : _uploadedCount / _selectedFiles.length,
                ),
              ),
            const SizedBox(height: AppTheme.spacing8),
          ],
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isUploading ? null : _pickFiles,
                  icon: const Icon(Icons.folder_open),
                  label: Text(_selectedFiles.isEmpty
                      ? '파일 선택'
                      : '추가 선택 (${_selectedFiles.length}개)'),
                ),
              ),
              const SizedBox(width: AppTheme.spacing8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isUploading || _selectedFiles.isEmpty ? null : _uploadFiles,
                  icon: _isUploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload),
                  label: Text(_isUploading
                      ? '업로드 중 ($_uploadedCount/${_selectedFiles.length})'
                      : '업로드'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'txt':
        return Icons.description;
      case 'mp3':
      case 'wav':
        return Icons.audio_file;
      case 'doc':
      case 'docx':
        return Icons.article;
      default:
        return Icons.file_present;
    }
  }
}
