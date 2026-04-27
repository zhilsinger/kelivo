import 'package:flutter/foundation.dart';
import '../models/agent_actor.dart';

/// Provider for agent work scope, team/workspace queries, and actor context.
///
/// Provides the current [AgentActor] to other providers and services.
/// In the future, this will manage team membership and workspace roles.
class AgentWorkProvider extends ChangeNotifier {
  AgentActor _currentActor;

  AgentWorkProvider({
    AgentActor? currentActor,
  }) : _currentActor = currentActor ?? const AgentActor(
          id: 'default',
          name: 'User',
          type: ActorType.user,
        );

  /// The currently active actor (user, assistant, or team).
  AgentActor get currentActor => _currentActor;

  /// Set the current actor context.
  void setCurrentActor(AgentActor actor) {
    _currentActor = actor;
    notifyListeners();
  }

  /// Whether agent work features are enabled for this workspace.
  bool get isEnabled => true; // Future: read from workspace settings

  /// Refresh workspace state (teams, permissions).
  Future<void> refresh() async {
    // Future: load team memberships, workspace roles
    notifyListeners();
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
  }
}