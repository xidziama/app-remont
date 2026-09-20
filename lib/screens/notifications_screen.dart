import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_notification.dart';
import '../models/company.dart';
import '../repositories/project_repository.dart';
import '../widgets/empty_state.dart';
import 'join_requests_screen.dart';
import 'project_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.company,
  });

  final CompanyMember company;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _markingAll = false;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
        ),
      );
  }

  Future<void> _markAllRead(ProjectRepository repository) async {
    setState(() => _markingAll = true);

    try {
      await repository.markAllNotificationsRead();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Не удалось отметить уведомления: $error');
    } finally {
      if (mounted) {
        setState(() => _markingAll = false);
      }
    }
  }

  Future<void> _openNotification({
    required ProjectRepository repository,
    required AppNotification notification,
  }) async {
    try {
      await repository.markNotificationRead(notification);

      if (!mounted) {
        return;
      }

      if (notification.type == AppNotificationType.joinRequestCreated &&
          widget.company.role.isOwner) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => JoinRequestsScreen(company: widget.company),
          ),
        );
        return;
      }

      final projectId = notification.projectId;
      if (projectId == null || projectId.isEmpty) {
        _showMessage('У уведомления нет связанного объекта.');
        return;
      }

      final project = await repository.getProjectById(projectId);
      if (!mounted) {
        return;
      }

      if (project == null) {
        _showMessage('Объект больше недоступен.');
        return;
      }

      // MVP открывает объект. Для точного открытия конкретного этапа позже
      // можно добавить route arguments или вложенный navigator.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProjectDetailScreen(
            project: project,
            company: widget.company,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Не удалось открыть уведомление: $error');
    }
  }

  IconData _iconFor(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.joinRequestCreated:
        return Icons.how_to_reg_outlined;
      case AppNotificationType.invitationAccepted:
        return Icons.mail_outline;
      case AppNotificationType.projectSentToDirectorReview:
      case AppNotificationType.projectSentToClientReview:
      case AppNotificationType.projectClosed:
        return Icons.apartment;
      case AppNotificationType.stageSentToReview:
      case AppNotificationType.stageApproved:
      case AppNotificationType.stageReturned:
        return Icons.task_alt;
      case AppNotificationType.workerAssignedToStage:
        return Icons.engineering_outlined;
      case AppNotificationType.receiptUploaded:
        return Icons.receipt_long;
    }
  }

  String _relativeTime(DateTime createdAt) {
    final difference = DateTime.now().difference(createdAt);

    if (difference.inMinutes < 1) {
      return 'только что';
    }

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} мин назад';
    }

    if (difference.inHours < 24) {
      return '${difference.inHours} ч назад';
    }

    if (difference.inDays < 7) {
      return '${difference.inDays} дн назад';
    }

    final day = createdAt.day.toString().padLeft(2, '0');
    final month = createdAt.month.toString().padLeft(2, '0');
    final year = createdAt.year.toString();
    return '$day.$month.$year';
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProjectRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Уведомления'),
        actions: [
          TextButton.icon(
            onPressed: _markingAll ? null : () => _markAllRead(repository),
            icon: _markingAll
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.done_all),
            label: const Text('Прочитано'),
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: repository.watchNotifications(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Не удалось загрузить уведомления',
              subtitle: snapshot.error.toString(),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data ?? const <AppNotification>[];
          if (notifications.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none,
              title: 'Уведомлений пока нет',
              subtitle:
                  'Здесь появятся заявки, этапы, чеки и статусы объектов.',
            );
          }

          return ListView.separated(
            key: const PageStorageKey<String>('notifications_list_scroll'),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return _NotificationTile(
                notification: notification,
                icon: _iconFor(notification.type),
                relativeTime: _relativeTime(notification.createdAt),
                onTap: () => _openNotification(
                  repository: repository,
                  notification: notification,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.icon,
    required this.relativeTime,
    required this.onTap,
  });

  final AppNotification notification;
  final IconData icon;
  final String relativeTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final unread = !notification.isRead;

    return Card(
      color: unread ? colorScheme.primaryContainer.withAlpha(82) : null,
      child: ListTile(
        minVerticalPadding: 14,
        leading: CircleAvatar(
          backgroundColor: unread
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          foregroundColor:
              unread ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
          child: Icon(icon),
        ),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                notification.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                    ),
              ),
            ),
            if (unread) ...[
              const SizedBox(width: 8),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notification.message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                relativeTime,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
