/// 페르소나 상태 관리 Provider
///
/// 페르소나 목록 조회, 생성, 파일 업로드 상태를 관리합니다.
/// [ApiService]를 통해 백엔드와 통신합니다.
import 'package:flutter/material.dart';
import '../models/persona_model.dart';
import '../services/api_service.dart';

class PersonaProvider extends ChangeNotifier {
  final ApiService apiService;
  
  List<Persona> _personas = [];
  Persona? _selectedPersona;
  bool _isLoading = false;
  String? _errorMessage;

  PersonaProvider(this.apiService);

  List<Persona> get personas => _personas;
  Persona? get selectedPersona => _selectedPersona;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadPersonas() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _personas = await apiService.getPersonas();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load personas: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createPersona(String name, String description) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newPersona = await apiService.createPersona(name, description);
      _personas.add(newPersona);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to create persona: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> uploadFileToPersona(String personaId, String filePath, String fileType) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final fileId = await apiService.uploadFile(personaId, filePath, fileType);
      
      // Update persona with new file
      final index = _personas.indexWhere((p) => p.id == personaId);
      if (index >= 0) {
        final updatedPersona = _personas[index];
        final updatedFileIds = [...updatedPersona.uploadedFileIds, fileId];
        _personas[index] = Persona(
          id: updatedPersona.id,
          name: updatedPersona.name,
          description: updatedPersona.description,
          uploadedFileIds: updatedFileIds,
          createdAt: updatedPersona.createdAt,
          messageCount: updatedPersona.messageCount,
        );
      }
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'File upload failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteFileFromPersona(String personaId, String fileId) async {
    try {
      await apiService.deleteFile(personaId, fileId);

      final index = _personas.indexWhere((p) => p.id == personaId);
      if (index >= 0) {
        final p = _personas[index];
        final updatedFileIds = p.uploadedFileIds.where((id) => id != fileId).toList();
        _personas[index] = Persona(
          id: p.id,
          name: p.name,
          description: p.description,
          uploadedFileIds: updatedFileIds,
          createdAt: p.createdAt,
          messageCount: p.messageCount,
        );
      }
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'File delete failed: $e';
      notifyListeners();
      return false;
    }
  }

  void selectPersona(Persona persona) {
    _selectedPersona = persona;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
