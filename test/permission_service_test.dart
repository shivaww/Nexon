import 'package:flutter_test/flutter_test.dart';
import 'package:nexon/services/permission/permission_service.dart';
import 'package:nexon/services/permission/permission_types.dart';

void main() {
  setUp(() => PermissionService.instance.reset());

  test('low risk auto-approves without user interaction', () async {
    final granted = await PermissionService.instance.requestToolPermission(
      toolId: 'read_file_rich',
      level: 1,
      description: 'read a file',
      requester: 'test',
    );
    expect(granted, isTrue);
    expect(PermissionService.instance.pendingCount, 0);
  });

  test('high risk stays pending until explicit approve', () async {
    final future = PermissionService.instance.requestToolPermission(
      toolId: 'execute_shell',
      level: 5,
      description: 'run command',
      requester: 'test',
    );
    expect(PermissionService.instance.pendingCount, 1);
    final req = PermissionService.instance.getPendingRequests().single;
    expect(req.level, PermissionLevel.dangerous);
    expect(PermissionService.instance.approvePermission(req.id), isTrue);
    expect(await future, isTrue);
    expect(PermissionService.instance.auditLogLength, 1);
  });

  test('deny resolves the waiting future with false', () async {
    final future = PermissionService.instance.requestToolPermission(
      toolId: 'delete_path',
      level: 7,
      description: 'delete file',
      requester: 'test',
    );
    final req = PermissionService.instance.getPendingRequests().single;
    expect(PermissionService.instance.denyPermission(req.id), isTrue);
    expect(await future, isFalse);
  });

  test('approving unknown request id returns false', () {
    expect(PermissionService.instance.approvePermission('nope'), isFalse);
  });

  test('auto-approve threshold is configurable', () async {
    PermissionService.instance.setAutoApproveLevel(3);
    final granted = await PermissionService.instance.requestToolPermission(
      toolId: 'run_analyzer',
      level: 3,
      description: 'static analysis',
      requester: 'test',
    );
    expect(granted, isTrue);
  });

  test('audit log records decisions and filters by tool', () async {
    await PermissionService.instance.requestToolPermission(
      toolId: 'read_file_rich',
      level: 0,
      description: 'meta',
      requester: 'test',
    );
    final history = PermissionService.instance.getApprovalHistory(
      toolId: 'read_file_rich',
    );
    expect(history, isNotEmpty);
    expect(
      PermissionService.instance.getApprovalHistory(toolId: 'never_used'),
      isEmpty,
    );
  });
}
