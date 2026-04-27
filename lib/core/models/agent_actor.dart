/// Actor types for agent work system (checklists, timers, audit).
enum ActorType {
  assistant,
  team,
  user,
  system,
}

/// Represents an actor in the agent work system.
class AgentActor {
  final String id;
  final String name;
  final ActorType type;

  const AgentActor({
    required this.id,
    required this.name,
    required this.type,
  });

  factory AgentActor.fromAssistant(dynamic assistant) {
    return AgentActor(
      id: assistant.id as String,
      name: (assistant.name as String?) ?? assistant.id,
      type: ActorType.assistant,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
  };

  factory AgentActor.fromJson(Map<String, dynamic> json) => AgentActor(
    id: json['id'] as String,
    name: json['name'] as String,
    type: ActorType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => ActorType.system,
    ),
  );
}