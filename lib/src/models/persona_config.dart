class PersonaConfig {
  final String personaId;
  final String name;
  final String avatarId;
  final String voiceId;
  final String? llmId;
  final String? systemPrompt;
  final int? maxSessionLengthSeconds;
  final String? languageCode;

  PersonaConfig({
    required this.personaId,
    required this.name,
    required this.avatarId,
    required this.voiceId,
    this.llmId,
    this.systemPrompt,
    this.maxSessionLengthSeconds,
    this.languageCode,
  });

  Map<String, dynamic> toJson() {
    return {
      'personaId': personaId,
      'name': name,
      'avatarId': avatarId,
      'voiceId': voiceId,
      if (llmId != null) 'llmId': llmId,
      if (systemPrompt != null) 'systemPrompt': systemPrompt,
      if (maxSessionLengthSeconds != null)
        'maxSessionLengthSeconds': maxSessionLengthSeconds,
      if (languageCode != null) 'languageCode': languageCode,
    };
  }

  factory PersonaConfig.fromJson(Map<String, dynamic> json) {
    return PersonaConfig(
      personaId: json['personaId'],
      name: json['name'],
      avatarId: json['avatarId'],
      voiceId: json['voiceId'],
      llmId: json['llmId'],
      systemPrompt: json['systemPrompt'],
      maxSessionLengthSeconds: json['maxSessionLengthSeconds'],
      languageCode: json['languageCode'],
    );
  }
}
