import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/persona_provider.dart';
import '../theme/app_theme.dart';

class CreatePersonaScreen extends StatefulWidget {
  const CreatePersonaScreen({Key? key}) : super(key: key);

  @override
  State<CreatePersonaScreen> createState() => _CreatePersonaScreenState();
}

class _CreatePersonaScreenState extends State<CreatePersonaScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('오류'),
        content: SingleChildScrollView(
          child: SelectableText(
            message,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _handleCreate(PersonaProvider personaProvider) async {
    if (_nameController.text.isEmpty) {
      _showErrorDialog('페르소나 이름을 입력해주세요.');
      return;
    }

    final success = await personaProvider.createPersona(
      _nameController.text,
      _descriptionController.text,
    );

    if (success) {
      if (mounted) {
        Navigator.pop(context);
      }
    } else {
      if (mounted) {
        _showErrorDialog(personaProvider.errorMessage ?? 'Failed to create persona');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Persona'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon preview
              Center(
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: const Color(0xFF6366F1),
                  child: Text(
                    _nameController.text.isNotEmpty
                        ? _nameController.text[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 32,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacing32),

              // Name field
              Text(
                'Persona Name',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppTheme.spacing8),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'e.g., Marketing Assistant, Data Analyst',
                  prefixIcon: Icon(Icons.edit),
                ),
                onChanged: (value) {
                  setState(() {}); // Update avatar
                },
              ),
              const SizedBox(height: AppTheme.spacing24),

              // Description field
              Text(
                'Description (Optional)',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppTheme.spacing8),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  hintText: 'Describe the purpose and skills of this persona',
                  prefixIcon: Icon(Icons.description),
                ),
                minLines: 3,
                maxLines: 5,
              ),
              const SizedBox(height: AppTheme.spacing32),

              // Create button
              Consumer<PersonaProvider>(
                builder: (context, personaProvider, _) {
                  return SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: personaProvider.isLoading
                          ? null
                          : () => _handleCreate(personaProvider),
                      child: personaProvider.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Create Persona'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
