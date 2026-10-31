import 'dart:math';

enum ApiOperation {
  createPairing,
  getPairing,
  completePairing,
  refreshSession,
  getSelfDevice,
  revokeSelfDevice,
  getDashboard,
  getTask,
  completeTask,
  getReminder,
  snoozeReminder,
  getMutation,
  submitChat,
  listChat,
  getChat,
  cancelChat,
  getPreferences,
  updatePreferences,
  updatePushRegistration,
  deletePushRegistration,
  getNotification,
  recordNotificationReceipt,
  getChatByClientId,
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
bool validUuid(Object? value) =>
    value is String && _uuidPattern.hasMatch(value);
String newActionKey() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class OperationRoute {
  final String method, path;
  final bool authenticated;
  const OperationRoute(this.method, this.path, this.authenticated);
  String resolve(String? id) {
    if (!path.contains('{')) {
      if (id != null) throw const FormatException('Unexpected resource');
      return path;
    }
    if (!validUuid(id)) throw const FormatException('Invalid resource');
    return path.replaceAll(RegExp(r'\{[^}]+\}'), id!);
  }
}

const operationRoutes = <ApiOperation, OperationRoute>{
  ApiOperation.createPairing: OperationRoute(
    'POST',
    '/mobile/v1/pairings',
    false,
  ),
  ApiOperation.getPairing: OperationRoute(
    'GET',
    '/mobile/v1/pairings/{pairing_id}',
    false,
  ),
  ApiOperation.completePairing: OperationRoute(
    'POST',
    '/mobile/v1/pairings/{pairing_id}/complete',
    false,
  ),
  ApiOperation.refreshSession: OperationRoute(
    'POST',
    '/mobile/v1/sessions/refresh',
    false,
  ),
  ApiOperation.getSelfDevice: OperationRoute(
    'GET',
    '/mobile/v1/devices/self',
    true,
  ),
  ApiOperation.revokeSelfDevice: OperationRoute(
    'DELETE',
    '/mobile/v1/devices/self',
    true,
  ),
  ApiOperation.getDashboard: OperationRoute(
    'GET',
    '/mobile/v1/dashboard',
    true,
  ),
  ApiOperation.getTask: OperationRoute(
    'GET',
    '/mobile/v1/tasks/{task_id}',
    true,
  ),
  ApiOperation.completeTask: OperationRoute(
    'POST',
    '/mobile/v1/tasks/{task_id}/complete',
    true,
  ),
  ApiOperation.getReminder: OperationRoute(
    'GET',
    '/mobile/v1/reminders/{reminder_id}',
    true,
  ),
  ApiOperation.snoozeReminder: OperationRoute(
    'POST',
    '/mobile/v1/reminders/{reminder_id}/snooze',
    true,
  ),
  ApiOperation.getMutation: OperationRoute(
    'GET',
    '/mobile/v1/mutations/{action_key}',
    true,
  ),
  ApiOperation.submitChat: OperationRoute(
    'POST',
    '/mobile/v1/chat/messages',
    true,
  ),
  ApiOperation.listChat: OperationRoute(
    'GET',
    '/mobile/v1/chat/messages',
    true,
  ),
  ApiOperation.getChat: OperationRoute(
    'GET',
    '/mobile/v1/chat/messages/{message_id}',
    true,
  ),
  ApiOperation.cancelChat: OperationRoute(
    'POST',
    '/mobile/v1/chat/messages/{message_id}/cancel',
    true,
  ),
  ApiOperation.getPreferences: OperationRoute(
    'GET',
    '/mobile/v1/preferences',
    true,
  ),
  ApiOperation.updatePreferences: OperationRoute(
    'PATCH',
    '/mobile/v1/preferences',
    true,
  ),
  ApiOperation.updatePushRegistration: OperationRoute(
    'PUT',
    '/mobile/v1/devices/self/push-registration',
    true,
  ),
  ApiOperation.deletePushRegistration: OperationRoute(
    'DELETE',
    '/mobile/v1/devices/self/push-registration',
    true,
  ),
  ApiOperation.getNotification: OperationRoute(
    'GET',
    '/mobile/v1/notifications/{notification_id}',
    true,
  ),
  ApiOperation.recordNotificationReceipt: OperationRoute(
    'POST',
    '/mobile/v1/notification-receipts',
    true,
  ),
  ApiOperation.getChatByClientId: OperationRoute(
    'GET',
    '/mobile/v1/chat/messages/by-client-id/{client_message_id}',
    true,
  ),
};
