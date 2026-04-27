// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get helloWorld => '你好，世界！';

  @override
  String get settingsPageBackButton => '返回';

  @override
  String get settingsPageTitle => '设置';

  @override
  String get settingsPageDarkMode => '深色';

  @override
  String get settingsPageLightMode => '浅色';

  @override
  String get settingsPageSystemMode => '跟随系统';

  @override
  String get settingsPageWarningMessage => '部分服务未配置，某些功能可能不可用';

  @override
  String get settingsPageGeneralSection => '通用设置';

  @override
  String get settingsPageColorMode => '颜色模式';

  @override
  String get settingsPageDisplay => '显示设置';

  @override
  String get settingsPageDisplaySubtitle => '界面主题与字号等外观设置';

  @override
  String get settingsPageAssistant => '助手';

  @override
  String get settingsPageAssistantSubtitle => '默认助手与对话风格';

  @override
  String get settingsPageModelsServicesSection => '模型与服务';

  @override
  String get settingsPageDefaultModel => '默认模型';

  @override
  String get settingsPageProviders => '供应商';

  @override
  String get settingsPageHotkeys => '快捷键';

  @override
  String get settingsPageSearch => '搜索服务';

  @override
  String get settingsPageTts => '语音服务';

  @override
  String get settingsPageMcp => 'MCP';

  @override
  String get settingsPageQuickPhrase => '快捷短语';

  @override
  String get settingsPageInstructionInjection => '指令注入';

  @override
  String get settingsPageDataSection => '数据设置';

  @override
  String get settingsPageBackup => '数据备份';

  @override
  String get settingsPageChatStorage => '聊天记录存储';

  @override
  String get settingsPageCalculating => '统计中…';

  @override
  String settingsPageFilesCount(int count, String size) {
    return '共 $count 个文件 · $size';
  }

  @override
  String get storageSpacePageTitle => '存储空间';

  @override
  String get storageSpaceRefreshTooltip => '刷新';

  @override
  String get storageSpaceLoadFailed => '加载失败';

  @override
  String get storageSpaceTotalLabel => '已用空间';

  @override
  String storageSpaceClearableLabel(String size) {
    return '可清理：$size';
  }

  @override
  String storageSpaceClearableHint(String size) {
    return '共发现可清理空间 $size';
  }

  @override
  String get storageSpaceCategoryImages => '图片';

  @override
  String get storageSpaceCategoryFiles => '文件';

  @override
  String get storageSpaceCategoryChatData => '聊天记录';

  @override
  String get storageSpaceCategoryAssistantData => '助手';

  @override
  String get storageSpaceCategoryCache => '缓存';

  @override
  String get storageSpaceCategoryLogs => '日志';

  @override
  String get storageSpaceCategoryOther => '应用';

  @override
  String storageSpaceFilesCount(int count) {
    return '$count 个文件';
  }

  @override
  String get storageSpaceSafeToClearHint => '可安全清理，不影响聊天记录。';

  @override
  String get storageSpaceNotSafeToClearHint => '可能影响聊天记录，请谨慎删除。';

  @override
  String get storageSpaceBreakdownTitle => '明细';

  @override
  String get storageSpaceSubChatMessages => '消息';

  @override
  String get storageSpaceSubChatConversations => '会话';

  @override
  String get storageSpaceSubChatToolEvents => '工具事件';

  @override
  String get storageSpaceSubAssistantAvatars => '头像';

  @override
  String get storageSpaceSubAssistantImages => '图片';

  @override
  String get storageSpaceSubCacheAvatars => '头像缓存';

  @override
  String get storageSpaceSubCacheOther => '其他缓存';

  @override
  String get storageSpaceSubCacheSystem => '系统缓存';

  @override
  String get storageSpaceSubLogsFlutter => '运行日志';

  @override
  String get storageSpaceSubLogsRequests => '网络日志';

  @override
  String get storageSpaceSubLogsOther => '其他日志';

  @override
  String get storageSpaceClearConfirmTitle => '确认清理';

  @override
  String storageSpaceClearConfirmMessage(String targetName) {
    return '确定要清理 $targetName 吗？';
  }

  @override
  String get storageSpaceClearButton => '清理';

  @override
  String storageSpaceClearDone(String targetName) {
    return '已清理 $targetName';
  }

  @override
  String storageSpaceClearFailed(String error) {
    return '清理失败：$error';
  }

  @override
  String get storageSpaceClearAvatarCacheButton => '清理头像缓存';

  @override
  String get storageSpaceClearCacheButton => '清理缓存';

  @override
  String get storageSpaceClearLogsButton => '清理日志';

  @override
  String get storageSpaceViewLogsButton => '查看日志';

  @override
  String get storageSpaceDeleteConfirmTitle => '确认删除';

  @override
  String storageSpaceDeleteUploadsConfirmMessage(int count) {
    return '删除 $count 个项目？删除后聊天记录中的附件可能无法打开。';
  }

  @override
  String storageSpaceDeletedUploadsDone(int count) {
    return '已删除 $count 个项目';
  }

  @override
  String get storageSpaceNoUploads => '暂无内容';

  @override
  String get storageSpaceSelectAll => '全选';

  @override
  String get storageSpaceClearSelection => '清空选择';

  @override
  String storageSpaceSelectedCount(int count) {
    return '已选 $count 项';
  }

  @override
  String storageSpaceUploadsCount(int count) {
    return '共 $count 项';
  }

  @override
  String get settingsPageAboutSection => '关于';

  @override
  String get settingsPageAbout => '关于';

  @override
  String get settingsPageDocs => '使用文档';

  @override
  String get settingsPageLogs => '日志';

  @override
  String get settingsPageSponsor => '赞助';

  @override
  String get settingsPageShare => '分享';

  @override
  String get sponsorPageMethodsSectionTitle => '赞助方式';

  @override
  String get sponsorPageSponsorsSectionTitle => '赞助用户';

  @override
  String get sponsorPageEmpty => '暂无赞助者';

  @override
  String get sponsorPageAfdianTitle => '爱发电';

  @override
  String get sponsorPageAfdianSubtitle => 'afdian.com/a/kelizo';

  @override
  String get sponsorPageWeChatTitle => '微信赞助';

  @override
  String get sponsorPageWeChatSubtitle => '微信赞助码';

  @override
  String get sponsorPageScanQrHint => '扫描二维码赞助';

  @override
  String get languageDisplaySimplifiedChinese => '简体中文';

  @override
  String get languageDisplayEnglish => 'English';

  @override
  String get languageDisplayTraditionalChinese => '繁體中文';

  @override
  String get languageDisplayJapanese => '日本語';

  @override
  String get languageDisplayKorean => '한국어';

  @override
  String get languageDisplayFrench => 'Français';

  @override
  String get languageDisplayGerman => 'Deutsch';

  @override
  String get languageDisplayItalian => 'Italiano';

  @override
  String get languageDisplaySpanish => 'Español';

  @override
  String get languageSelectSheetTitle => '选择翻译语言';

  @override
  String get languageSelectSheetClearButton => '清空翻译';

  @override
  String get homePageClearContext => '清空上下文';

  @override
  String homePageClearContextWithCount(String actual, String configured) {
    return '清空上下文 ($actual/$configured)';
  }

  @override
  String get homePageDefaultAssistant => '默认助手';

  @override
  String get mermaidExportPng => '导出 PNG';

  @override
  String get mermaidExportFailed => '导出失败';

  @override
  String get mermaidPreviewOpen => '浏览器预览';

  @override
  String get mermaidPreviewOpenFailed => '无法打开预览';

  @override
  String get assistantProviderDefaultAssistantName => '默认助手';

  @override
  String get assistantProviderSampleAssistantName => '示例助手';

  @override
  String get assistantProviderNewAssistantName => '新助手';

  @override
  String assistantProviderSampleAssistantSystemPrompt(
    String model_name,
    String cur_datetime,
    String locale,
    String timezone,
    String device_info,
    String system_version,
  ) {
    return '你是$model_name, 一个人工智能助手，乐意为用户提供准确，有益的帮助。现在时间是$cur_datetime，用户设备语言为$locale，时区为$timezone，用户正在使用$device_info，版本$system_version。如果用户没有明确说明，请使用用户设备语言进行回复。';
  }

  @override
  String get displaySettingsPageLanguageTitle => '应用语言';

  @override
  String get displaySettingsPageLanguageSubtitle => '选择界面语言';

  @override
  String get assistantTagsManageTitle => '管理标签';

  @override
  String get assistantTagsCreateButton => '创建';

  @override
  String get assistantTagsCreateDialogTitle => '创建标签';

  @override
  String get assistantTagsCreateDialogOk => '创建';

  @override
  String get assistantTagsCreateDialogCancel => '取消';

  @override
  String get assistantTagsNameHint => '标签名称';

  @override
  String get assistantTagsRenameButton => '重命名';

  @override
  String get assistantTagsRenameDialogTitle => '重命名标签';

  @override
  String get assistantTagsRenameDialogOk => '重命名';

  @override
  String get assistantTagsDeleteButton => '删除';

  @override
  String get assistantTagsDeleteConfirmTitle => '删除标签';

  @override
  String get assistantTagsDeleteConfirmContent => '确定要删除该标签吗？';

  @override
  String get assistantTagsDeleteConfirmOk => '删除';

  @override
  String get assistantTagsDeleteConfirmCancel => '取消';

  @override
  String get assistantTagsContextMenuEditAssistant => '编辑助手';

  @override
  String get assistantTagsContextMenuManageTags => '管理标签';

  @override
  String get mcpTransportOptionStdio => 'STDIO';

  @override
  String get mcpTransportTagStdio => 'STDIO';

  @override
  String get mcpTransportTagInmemory => '内置';

  @override
  String get mcpTransportTagSse => 'SSE';

  @override
  String get mcpTransportTagHttp => 'HTTP';

  @override
  String get mcpServerEditSheetStdioOnlyDesktop => 'STDIO 仅在桌面端可用';

  @override
  String get mcpServerEditSheetStdioCommandLabel => '命令';

  @override
  String get mcpServerEditSheetStdioArgumentsLabel => '参数';

  @override
  String get mcpServerEditSheetStdioWorkingDirectoryLabel => '工作目录（可选）';

  @override
  String get mcpServerEditSheetStdioEnvironmentTitle => '环境变量';

  @override
  String get mcpServerEditSheetStdioEnvNameLabel => '名称';

  @override
  String get mcpServerEditSheetStdioEnvValueLabel => '值';

  @override
  String get mcpServerEditSheetStdioAddEnv => '添加环境变量';

  @override
  String get mcpServerEditSheetStdioCommandRequired => 'STDIO 需要填写命令';

  @override
  String get assistantTagsContextMenuDeleteAssistant => '删除助手';

  @override
  String get assistantTagsClearTag => '清除标签';

  @override
  String get displaySettingsPageLanguageChineseLabel => '简体中文';

  @override
  String get displaySettingsPageLanguageEnglishLabel => 'English';

  @override
  String get homePagePleaseSelectModel => '请先选择模型';

  @override
  String get homePageAudioAttachmentUnsupported =>
      '当前模型不支持音频附件，请切换到支持音频输入的模型或移除音频文件后重试。';

  @override
  String get homePagePleaseSetupTranslateModel => '请先设置翻译模型';

  @override
  String get homePageTranslating => '翻译中...';

  @override
  String homePageTranslateFailed(String error) {
    return '翻译失败: $error';
  }

  @override
  String get chatServiceDefaultConversationTitle => '新对话';

  @override
  String get userProviderDefaultUserName => '用户';

  @override
  String get homePageDeleteMessage => '删除本版本';

  @override
  String get homePageDeleteMessageConfirm => '确定要删除当前版本吗？此操作不可撤销。';

  @override
  String get homePageDeleteAllVersions => '删除全部版本';

  @override
  String get homePageDeleteAllVersionsConfirm => '确定要删除这条消息的全部版本吗？此操作不可撤销。';

  @override
  String get homePageCancel => '取消';

  @override
  String get homePageDelete => '删除';

  @override
  String get homePageSelectMessagesToShare => '请选择要分享的消息';

  @override
  String get homePageDone => '完成';

  @override
  String get homePageDropToUpload => '将文件拖拽到此处上传';

  @override
  String get assistantEditPageTitle => '助手';

  @override
  String get assistantEditPageNotFound => '助手不存在';

  @override
  String get assistantEditPageBasicTab => '基础设置';

  @override
  String get assistantEditPagePromptsTab => '提示词';

  @override
  String get assistantEditPageMcpTab => 'MCP';

  @override
  String get assistantEditPageQuickPhraseTab => '快捷短语';

  @override
  String get assistantEditPageCustomTab => '自定义请求';

  @override
  String get assistantEditPageRegexTab => '正则替换';

  @override
  String get assistantEditRegexDescription => '为用户/助手消息配置正则规则，可修改或仅调整显示效果。';

  @override
  String get assistantEditAddRegexButton => '添加正则规则';

  @override
  String get assistantRegexAddTitle => '添加正则规则';

  @override
  String get assistantRegexEditTitle => '编辑正则规则';

  @override
  String get assistantRegexNameLabel => '规则名称';

  @override
  String get assistantRegexPatternLabel => '正则表达式';

  @override
  String get assistantRegexReplacementLabel => '替换字符串';

  @override
  String get assistantRegexScopeLabel => '影响范围';

  @override
  String get assistantRegexScopeUser => '用户';

  @override
  String get assistantRegexScopeAssistant => '助手';

  @override
  String get assistantRegexScopeVisualOnly => '仅视觉';

  @override
  String get assistantRegexScopeReplaceOnly => '仅替换';

  @override
  String get assistantRegexAddAction => '添加';

  @override
  String get assistantRegexSaveAction => '保存';

  @override
  String get assistantRegexDeleteButton => '删除';

  @override
  String get assistantRegexValidationError => '请填写名称、正则表达式，并至少选择一个范围。';

  @override
  String get assistantRegexInvalidPattern => '正则表达式无效';

  @override
  String get assistantRegexCancelButton => '取消';

  @override
  String get assistantRegexUntitled => '未命名规则';

  @override
  String get assistantEditCustomHeadersTitle => '自定义 Header';

  @override
  String get assistantEditCustomHeadersAdd => '添加 Header';

  @override
  String get assistantEditCustomHeadersEmpty => '未添加 Header';

  @override
  String get assistantEditCustomBodyTitle => '自定义 Body';

  @override
  String get assistantEditCustomBodyAdd => '添加 Body';

  @override
  String get assistantEditCustomBodyEmpty => '未添加 Body 项';

  @override
  String get assistantEditHeaderNameLabel => 'Header 名称';

  @override
  String get assistantEditHeaderValueLabel => 'Header 值';

  @override
  String get assistantEditBodyKeyLabel => 'Body Key';

  @override
  String get assistantEditBodyValueLabel => 'Body 值 (JSON)';

  @override
  String get assistantEditDeleteTooltip => '删除';

  @override
  String get assistantEditAssistantNameLabel => '助手名称';

  @override
  String get assistantEditUseAssistantAvatarTitle => '使用助手头像';

  @override
  String get assistantEditUseAssistantAvatarSubtitle => '在聊天中使用助手头像替代模型头像';

  @override
  String get assistantEditUseAssistantNameTitle => '使用助手名字';

  @override
  String get assistantEditChatModelTitle => '聊天模型';

  @override
  String get assistantEditChatModelSubtitle => '为该助手设置默认聊天模型（未设置时使用全局默认）';

  @override
  String get assistantEditTemperatureDescription => '控制输出的随机性，范围 0–2';

  @override
  String get assistantEditTopPDescription => '请不要修改此值，除非你知道自己在做什么';

  @override
  String get assistantEditParameterDisabled => '已关闭（使用服务商默认）';

  @override
  String get assistantEditParameterDisabled2 => '已关闭（无限制）';

  @override
  String get assistantEditContextMessagesTitle => '上下文消息数量';

  @override
  String get assistantEditContextMessagesDescription =>
      '多少历史消息会被当作上下文发送给模型，超过数量会忽略，只保留最近 N 条';

  @override
  String get assistantEditStreamOutputTitle => '流式输出';

  @override
  String get assistantEditStreamOutputDescription => '是否启用消息的流式输出';

  @override
  String get assistantEditThinkingBudgetTitle => '思考预算';

  @override
  String get assistantEditConfigureButton => '配置';

  @override
  String get assistantEditMaxTokensTitle => '最大 Token 数';

  @override
  String get assistantEditMaxTokensDescription => '留空表示无限制';

  @override
  String get assistantEditMaxTokensHint => '无限制';

  @override
  String get assistantEditChatBackgroundTitle => '聊天背景';

  @override
  String get assistantEditChatBackgroundDescription => '设置助手聊天页面的背景图片';

  @override
  String get assistantEditChooseImageButton => '选择背景图片';

  @override
  String get assistantEditClearButton => '清除';

  @override
  String get desktopNavChatTooltip => '聊天';

  @override
  String get desktopNavTranslateTooltip => '翻译';

  @override
  String get desktopNavStorageTooltip => '存储';

  @override
  String get desktopNavGlobalSearchTooltip => '全局搜索';

  @override
  String get desktopNavThemeToggleTooltip => '主题切换';

  @override
  String get desktopNavSettingsTooltip => '设置';

  @override
  String get desktopAvatarMenuUseEmoji => '使用表情符号';

  @override
  String get cameraPermissionDeniedMessage => '未授予相机权限';

  @override
  String get openSystemSettings => '去设置';

  @override
  String get desktopAvatarMenuChangeFromImage => '从图片更换…';

  @override
  String get desktopAvatarMenuReset => '重置头像';

  @override
  String get assistantEditAvatarChooseImage => '选择图片';

  @override
  String get assistantEditAvatarChooseEmoji => '选择表情';

  @override
  String get assistantEditAvatarEnterLink => '输入链接';

  @override
  String get assistantEditAvatarImportQQ => 'QQ头像';

  @override
  String get assistantEditAvatarReset => '重置';

  @override
  String get displaySettingsPageChatMessageBackgroundTitle => '聊天消息背景';

  @override
  String get displaySettingsPageChatMessageBackgroundDefault => '默认';

  @override
  String get displaySettingsPageChatMessageBackgroundFrosted => '模糊';

  @override
  String get displaySettingsPageChatMessageBackgroundSolid => '纯色';

  @override
  String get displaySettingsPageAndroidBackgroundChatTitle => '后台聊天生成';

  @override
  String get androidBackgroundStatusOn => '开启';

  @override
  String get androidBackgroundStatusOff => '关闭';

  @override
  String get androidBackgroundStatusOther => '开启并通知';

  @override
  String get androidBackgroundOptionOn => '开启';

  @override
  String get androidBackgroundOptionOnNotify => '开启并在生成完时发送消息';

  @override
  String get androidBackgroundOptionOff => '关闭';

  @override
  String get notificationChatCompletedTitle => '生成完成';

  @override
  String get notificationChatCompletedBody => '助手回复已生成';

  @override
  String get androidBackgroundNotificationTitle => 'Kelizo 正在运行';

  @override
  String get androidBackgroundNotificationText => '后台保持聊天生成';

  @override
  String get assistantEditEmojiDialogTitle => '选择表情';

  @override
  String get assistantEditEmojiDialogHint => '输入或粘贴任意表情';

  @override
  String get assistantEditEmojiDialogCancel => '取消';

  @override
  String get assistantEditEmojiDialogSave => '保存';

  @override
  String get assistantEditImageUrlDialogTitle => '输入图片链接';

  @override
  String get assistantEditImageUrlDialogHint =>
      '例如: https://example.com/avatar.png';

  @override
  String get assistantEditImageUrlDialogCancel => '取消';

  @override
  String get assistantEditImageUrlDialogSave => '保存';

  @override
  String get assistantEditQQAvatarDialogTitle => '使用QQ头像';

  @override
  String get assistantEditQQAvatarDialogHint => '输入QQ号码（5-12位）';

  @override
  String get assistantEditQQAvatarRandomButton => '随机QQ';

  @override
  String get assistantEditQQAvatarFailedMessage => '获取随机QQ头像失败，请重试';

  @override
  String get assistantEditQQAvatarDialogCancel => '取消';

  @override
  String get assistantEditQQAvatarDialogSave => '保存';

  @override
  String get assistantEditGalleryErrorMessage => '无法打开相册，试试输入图片链接';

  @override
  String get assistantEditGeneralErrorMessage => '发生错误，试试输入图片链接';

  @override
  String get providerDetailPageMultiKeyModeTitle => '多Key模式';

  @override
  String get providerDetailPageManageKeysButton => '多Key管理';

  @override
  String get multiKeyPageTitle => '多Key管理';

  @override
  String get multiKeyPageDetect => '检测';

  @override
  String get multiKeyPageAdd => '添加';

  @override
  String get multiKeyPageAddHint => '请输入API Key（多个用逗号或空格分隔）';

  @override
  String multiKeyPageImportedSnackbar(int n) {
    return '已导入$n个key';
  }

  @override
  String get multiKeyPagePleaseAddModel => '请先添加模型';

  @override
  String get multiKeyPageTotal => '总数';

  @override
  String get multiKeyPageNormal => '正常';

  @override
  String get multiKeyPageError => '错误';

  @override
  String get multiKeyPageAccuracy => '正确率';

  @override
  String get multiKeyPageStrategyTitle => '负载均衡策略';

  @override
  String get multiKeyPageStrategyRoundRobin => '轮询';

  @override
  String get multiKeyPageStrategyPriority => '优先级';

  @override
  String get multiKeyPageStrategyLeastUsed => '最少使用';

  @override
  String get multiKeyPageStrategyRandom => '随机';

  @override
  String get multiKeyPageNoKeys => '暂无Key';

  @override
  String get multiKeyPageStatusActive => '正常';

  @override
  String get multiKeyPageStatusDisabled => '已关闭';

  @override
  String get multiKeyPageStatusError => '错误';

  @override
  String get multiKeyPageStatusRateLimited => '限速';

  @override
  String get multiKeyPageEditAlias => '编辑别名';

  @override
  String get multiKeyPageEdit => '编辑';

  @override
  String get multiKeyPageKey => 'API Key';

  @override
  String get multiKeyPagePriority => '优先级（1–10）';

  @override
  String get multiKeyPageDuplicateKeyWarning => '该 Key 已存在';

  @override
  String get multiKeyPageAlias => '别名';

  @override
  String get multiKeyPageCancel => '取消';

  @override
  String get multiKeyPageSave => '保存';

  @override
  String get multiKeyPageDelete => '删除';

  @override
  String get assistantEditSystemPromptTitle => '系统提示词';

  @override
  String get assistantEditSystemPromptHint => '输入系统提示词…';

  @override
  String get assistantEditSystemPromptImportButton => '从文件导入';

  @override
  String get assistantEditSystemPromptImportSuccess => '已从文件更新系统提示词';

  @override
  String get assistantEditSystemPromptImportFailed => '导入失败';

  @override
  String get assistantEditSystemPromptImportEmpty => '文件内容为空';

  @override
  String get assistantEditAvailableVariables => '可用变量：';

  @override
  String get assistantEditVariableDate => '日期';

  @override
  String get assistantEditVariableTime => '时间';

  @override
  String get assistantEditVariableDatetime => '日期和时间';

  @override
  String get assistantEditVariableModelId => '模型ID';

  @override
  String get assistantEditVariableModelName => '模型名称';

  @override
  String get assistantEditVariableLocale => '语言环境';

  @override
  String get assistantEditVariableTimezone => '时区';

  @override
  String get assistantEditVariableSystemVersion => '系统版本';

  @override
  String get assistantEditVariableDeviceInfo => '设备信息';

  @override
  String get assistantEditVariableBatteryLevel => '电池电量';

  @override
  String get assistantEditVariableNickname => '用户昵称';

  @override
  String get assistantEditVariableAssistantName => '助手名称';

  @override
  String get assistantEditMessageTemplateTitle => '聊天内容模板';

  @override
  String get assistantEditVariableRole => '助手';

  @override
  String get assistantEditVariableMessage => '内容';

  @override
  String get assistantEditPreviewTitle => '预览';

  @override
  String get codeBlockPreviewButton => '预览';

  @override
  String codeBlockCollapsedLines(int n) {
    return '… 已折叠 $n 行';
  }

  @override
  String get htmlPreviewNotSupportedOnLinux => 'Linux 暂不支持 HTML 预览';

  @override
  String get assistantEditSampleUser => '用户';

  @override
  String get assistantEditSampleMessage => '你好啊';

  @override
  String get assistantEditSampleReply => '你好，有什么我可以帮你的吗？';

  @override
  String get assistantEditMcpNoServersMessage => '暂无已启动的 MCP 服务器';

  @override
  String get assistantEditMcpConnectedTag => '已连接';

  @override
  String assistantEditMcpToolsCountTag(String enabled, String total) {
    return '工具: $enabled/$total';
  }

  @override
  String get assistantEditModelUseGlobalDefault => '使用全局默认';

  @override
  String get assistantSettingsPageTitle => '助手设置';

  @override
  String get assistantSettingsDefaultTag => '默认';

  @override
  String get assistantSettingsCopyButton => '复制';

  @override
  String get assistantSettingsCopySuccess => '已复制助手';

  @override
  String get assistantSettingsCopySuffix => '副本';

  @override
  String get assistantSettingsCloneSheetTitle => '克隆助手';

  @override
  String get assistantSettingsCloneSheetMakeClones => '创建克隆';

  @override
  String assistantSettingsCloneSuccessMultiple(int count) {
    return '已克隆 $count 个助手';
  }

  @override
  String get assistantEditExportButton => '导出配置';

  @override
  String get assistantEditExportSuccess => '助手配置已导出';

  @override
  String get assistantSettingsDeleteButton => '删除';
