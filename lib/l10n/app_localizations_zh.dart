// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get ok => '确定';

  @override
  String get add => '添加';

  @override
  String get remove => '移除';

  @override
  String get duplicate => '复制';

  @override
  String get windowTitleAdministrator => 'trayforge（管理员）';

  @override
  String get trayReloadSettings => '重新加载设置';

  @override
  String get trayDashboard => '仪表盘';

  @override
  String get trayExit => '退出';

  @override
  String get kindProcess => '进程';

  @override
  String get kindServiceGroup => '服务组';

  @override
  String get dashboardTitle => '仪表盘';

  @override
  String get dashboardSwitchToGrid => '切换到网格视图';

  @override
  String get dashboardSwitchToList => '切换到列表视图';

  @override
  String get dashboardAddProcess => '添加进程';

  @override
  String get dashboardAddServiceGroup => '添加服务组';

  @override
  String get dashboardAddProcessButton => '添加进程';

  @override
  String get dashboardAddServiceGroupButton => '添加服务组';

  @override
  String get dashboardSettings => '设置';

  @override
  String get dashboardEmpty => '尚未配置任何进程或服务组';

  @override
  String get configErrorTitle => '配置错误';

  @override
  String get configErrorBody => '配置文件已损坏，并已备份。请检查你的配置文件。';

  @override
  String get editProcessTooltip => '编辑进程';

  @override
  String get processClearOutput => '清空输出';

  @override
  String get processSearchOutput => '搜索输出';

  @override
  String get processCloseSearch => '关闭搜索';

  @override
  String get processFilterHint => '筛选输出…';

  @override
  String get processNoMatchingLines => '没有匹配的行';

  @override
  String get noOutputYet => '暂无输出';

  @override
  String get toggleStart => '启动';

  @override
  String get toggleStop => '停止';

  @override
  String get copyWebuiTooltip => '复制 WebUI 地址（右键：在浏览器中打开）';

  @override
  String get urlCopied => '已复制地址';

  @override
  String get editCommandTitle => '编辑命令';

  @override
  String get editCommandHint => '输入命令（Ctrl+Enter 保存）';

  @override
  String get fieldName => '名称 *';

  @override
  String get fieldNameHelper => '不能包含 / 或 \\';

  @override
  String get nameRequired => '名称为必填项';

  @override
  String get nameSeparator => '名称不能包含 / 或 \\';

  @override
  String get fieldCwd => '工作目录（cwd）';

  @override
  String get fieldCwdHint => '例如 C:\\MyApp';

  @override
  String get browseTooltip => '浏览…';

  @override
  String get fieldCommand => '命令 *';

  @override
  String get fieldCommandHint => '例如 myapp.exe --flag';

  @override
  String get commandRequired => '命令为必填项';

  @override
  String get multiLineEditorTooltip => '多行编辑器…';

  @override
  String get fieldEncoding => '编码';

  @override
  String get singletonTitle => '单实例';

  @override
  String get singletonSubtitle => '若已有同名进程在运行，则不再启动';

  @override
  String get autostartTitle => '自动启动';

  @override
  String get autostartSubtitle => 'TrayForge 启动时自动启动此进程';

  @override
  String get cleanupCwdTitle => '清理工作目录';

  @override
  String get cleanupCwdSubtitle => '启动前结束同一工作目录下的残留进程';

  @override
  String get elevatedTitle => '以管理员身份运行';

  @override
  String get elevatedSubtitle =>
      '以管理员权限启动。仅当 TrayForge 自身未提权时 Windows 才会弹出 UAC 提示；若已提权，输出和环境变量会像普通进程一样被捕获。';

  @override
  String get fieldWebuiPattern => 'WebUI 匹配模式';

  @override
  String get fieldWebuiPatternHint => '例如 WebUI started at (http://[\\d.:]+)';

  @override
  String get fieldLogFile => '日志文件';

  @override
  String get fieldLogFileHelper =>
      '将该文件的新增内容导入输出窗格（相对 cwd）。当 TrayForge 未提权时，这是提权进程唯一的输出通道。';

  @override
  String get fieldLogFileHint => '例如 logs\\app.log';

  @override
  String get fieldMaxRestarts => '最大重启次数';

  @override
  String get fieldMaxRestartsHint => '例如 3';

  @override
  String get deleteBeforeStartTitle => '启动前删除';

  @override
  String get deleteBeforeStartHelper => '每行一个文件路径，相对于工作目录';

  @override
  String get deleteBeforeStartHint => 'temp.lock\ncache.dat';

  @override
  String get envVarsTitle => '环境变量';

  @override
  String get fieldKey => '键';

  @override
  String get fieldValue => '值';

  @override
  String get processEditTitle => '编辑进程';

  @override
  String get processAddTitle => '添加进程';

  @override
  String get processRunningNotice => '进程正在运行 — 更改将在下次启动时生效';

  @override
  String get processDeleteTitle => '删除进程？';

  @override
  String get processDeleteRunningTitle => '停止并删除？';

  @override
  String processDeleteBody(String name) {
    return '删除“$name”？此操作无法撤销。';
  }

  @override
  String processDeleteRunningBody(String name) {
    return '“$name”正在运行。它将被停止，配置将被删除。';
  }

  @override
  String get processDeleteRunningAction => '停止并删除';

  @override
  String get editServiceGroupTooltip => '编辑服务组';

  @override
  String get serviceStartTooltip => '启动服务';

  @override
  String get serviceStopTooltip => '停止服务';

  @override
  String serviceSummary(int running, int total, String state) {
    return '$running/$total 运行中 · $state';
  }

  @override
  String serviceGridSummary(int running, int total) {
    return '$running/$total 运行中';
  }

  @override
  String get serviceEditTitle => '编辑服务组';

  @override
  String get serviceAddTitle => '添加服务组';

  @override
  String get serviceDeleteTitle => '删除服务组？';

  @override
  String serviceDeleteBody(String name) {
    return '从 TrayForge 中移除“$name”？\n\n服务本身会继续运行 — TrayForge 只是不再管理它们。';
  }

  @override
  String get serviceClearLog => '清空日志';

  @override
  String get serviceQuerying => '正在查询服务…';

  @override
  String get serviceNoActivity => '暂无活动';

  @override
  String get fieldServices => '服务 *';

  @override
  String get fieldServicesHelper =>
      '每行一个 Windows 服务名（或 systemd 单元），它们会被一起启动和停止。';

  @override
  String get fieldServicesHint => 'Spooler\nMyService';

  @override
  String get servicesRequired => '至少需要一个服务';

  @override
  String get stopDependentsTitle => '同时停止依赖服务';

  @override
  String get stopDependentsSubtitle => '若因其他服务依赖某个成员而导致停止失败，请先停止这些依赖服务。';

  @override
  String get serviceElevationNote =>
      '控制操作需要管理员权限：TrayForge 每次启动/停止会请求一次。状态查询不会弹出提示。';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsOutputRefresh => '输出刷新间隔（毫秒）';

  @override
  String get settingsOutputRefreshTip => '越低越流畅，越高越省 CPU';

  @override
  String get settingsHistoryLimit => '历史行数上限';

  @override
  String get settingsHistoryLimitTip => '每个进程保留的最大行数';

  @override
  String get settingsServicePoll => '服务轮询间隔（毫秒）';

  @override
  String get settingsServicePollTip => '服务组重新查询状态的频率。状态查询不会请求提权。';

  @override
  String get settingsAppliesImmediately => '立即生效';

  @override
  String get settingsTakesEffectOnStart => '在进程下次启动时生效';

  @override
  String get settingsAutostart => '开机自启';

  @override
  String get settingsReload => '从磁盘重新加载配置';

  @override
  String get settingsReloadSubtitle =>
      '重新读取 config.json，无需重启即可应用进程与服务变更。从文件中移除的进程会被停止。';

  @override
  String get settingsReloaded => '配置已重新加载';

  @override
  String get settingsReloadFailed => '无法读取 config.json（损坏的文件已备份在其旁边）';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageSystem => '跟随系统';

  @override
  String get stateStopped => '已停止';

  @override
  String get stateStarting => '启动中';

  @override
  String get stateRunning => '运行中';

  @override
  String get stateStopping => '停止中';

  @override
  String get stateCrashed => '已崩溃';

  @override
  String get stateCooldown => '冷却中';

  @override
  String get serviceStateNotInstalled => '未安装';

  @override
  String get serviceStatePaused => '已暂停';

  @override
  String get serviceStateFailed => '失败';

  @override
  String get serviceStateUnknown => '未知';

  @override
  String validationEmptyName(String kind) {
    return '$kind名称不能为空';
  }

  @override
  String validationNameSeparator(String kind, String name) {
    return '$kind名称“$name”不能包含 / 或 \\';
  }

  @override
  String validationNoServices(String name) {
    return '服务组“$name”至少需要一个服务';
  }

  @override
  String validationWebuiPattern(String message) {
    return '无效的 webui_pattern 正则表达式：$message';
  }
}
