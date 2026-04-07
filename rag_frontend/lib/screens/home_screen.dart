import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/persona_model.dart';
import '../providers/auth_provider.dart';
import '../providers/persona_provider.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Load personas when screen initializes
    Future.microtask(() {
      context.read<PersonaProvider>().loadPersonas();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Personas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        context.read<AuthProvider>().logout();
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/create-persona');
        },
        tooltip: 'Create Persona',
        child: const Icon(Icons.add),
      ),
      body: Consumer<PersonaProvider>(
        builder: (context, personaProvider, _) {
          if (personaProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (personaProvider.personas.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_off,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: AppTheme.spacing16),
                  Text(
                    'No Personas Yet',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppTheme.spacing8),
                  Text(
                    'Create your first persona to get started',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.spacing24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/create-persona');
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Create Persona'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppTheme.spacing16),
            itemCount: personaProvider.personas.length,
            itemBuilder: (context, index) {
              final persona = personaProvider.personas[index];
              return PersonaCard(persona: persona);
            },
          );
        },
      ),
    );
  }
}

class PersonaCard extends StatelessWidget {
  final Persona persona;

  const PersonaCard({
    Key? key,
    required this.persona,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(AppTheme.spacing16),
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: const Color(0xFF6366F1),
          child: Text(
            persona.name.isNotEmpty ? persona.name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
        title: Text(
          persona.name,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              persona.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${persona.messageCount} messages · ${persona.uploadedFileIds.length} files',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: Colors.grey,
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          context.read<PersonaProvider>().selectPersona(persona);
          Navigator.pushNamed(context, '/chat', arguments: persona);
        },
      ),
    );
  }
}
