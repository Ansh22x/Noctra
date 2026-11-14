import 'dart:async';
import 'dart:collection';
import '../utils/noctra_logger.dart';

/// Priority levels for queued concurrent operations.
enum TaskPriority {
  immediate,
  high,
  normal,
  low,
}

/// A queued unit of work managed by [ConcurrencyController].
class _QueuedTask<T> {
  final Future<T> Function() computation;
  final Completer<T> completer;
  final TaskPriority priority;
  final String label;
  final DateTime enqueuedAt;

  _QueuedTask({
    required this.computation,
    required this.completer,
    required this.priority,
    required this.label,
    required this.enqueuedAt,
  });
}

/// Robust, bounded concurrency controller for asynchronous pipelines in Noctra.
///
/// Features:
///  - Strict upper bound on simultaneous tasks in flight ([maxConcurrent]).
///  - Priority-aware FIFO queue to ensure critical foreground operations
///    (e.g., active track resolution) preempt bulk background jobs.
///  - Task cancellation and timeout guards to prevent hung slots.
///  - Observable real-time metrics for Developer Suite telemetry.
class ConcurrencyController {
  final String name;
  final int maxConcurrent;
  final Duration? defaultTimeout;

  int _activeCount = 0;
  int _completedCount = 0;
  int _failedCount = 0;

  final ListQueue<_QueuedTask<dynamic>> _queue = ListQueue<_QueuedTask<dynamic>>();

  ConcurrencyController({
    required this.name,
    required this.maxConcurrent,
    this.defaultTimeout,
  }) : assert(maxConcurrent > 0, 'maxConcurrent must be greater than zero');

  /// Active tasks currently executing.
  int get activeCount => _activeCount;

  /// Tasks waiting in queue to be executed.
  int get queuedCount => _queue.length;

  /// Total successfully completed tasks.
  int get completedCount => _completedCount;

  /// Total failed tasks.
  int get failedCount => _failedCount;

  /// Schedules [task] for execution within the bounded concurrency slot pool.
  Future<T> run<T>(
    Future<T> Function() task, {
    TaskPriority priority = TaskPriority.normal,
    String? label,
    Duration? timeout,
  }) {
    final taskLabel = label ?? 'task_${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<T>();

    final queued = _QueuedTask<T>(
      computation: task,
      completer: completer,
      priority: priority,
      label: taskLabel,
      enqueuedAt: DateTime.now(),
    );

    if (_activeCount < maxConcurrent) {
      _executeTask(queued);
    } else {
      _enqueue(queued);
    }

    return completer.future;
  }

  void _enqueue(_QueuedTask<dynamic> task) {
    if (task.priority == TaskPriority.immediate) {
      // Immediate tasks jump to the front of the queue
      _queue.addFirst(task);
    } else {
      // Insert in priority order
      final index = _queue.toList().indexWhere((t) => t.priority.index > task.priority.index);
      if (index == -1) {
        _queue.addLast(task);
      } else {
        final list = _queue.toList();
        list.insert(index, task);
        _queue.clear();
        _queue.addAll(list);
      }
    }
  }

  Future<void> _executeTask(_QueuedTask<dynamic> task) async {
    _activeCount++;
    final effectiveTimeout = defaultTimeout;

    try {
      Future<dynamic> execution = task.computation();
      if (effectiveTimeout != null) {
        execution = execution.timeout(
          effectiveTimeout,
          onTimeout: () => throw TimeoutException('Task ${task.label} timed out after $effectiveTimeout'),
        );
      }

      final result = await execution;
      _completedCount++;
      if (!task.completer.isCompleted) {
        task.completer.complete(result);
      }
    } catch (error, stackTrace) {
      _failedCount++;
      NoctraLogger.w('ConcurrencyController [$name] task ${task.label} failed: $error');
      if (!task.completer.isCompleted) {
        task.completer.completeError(error, stackTrace);
      }
    } finally {
      _activeCount--;
      _drain();
    }
  }

  void _drain() {
    while (_activeCount < maxConcurrent && _queue.isNotEmpty) {
      final next = _queue.removeFirst();
      _executeTask(next);
    }
  }

  /// Cancels all pending tasks in the queue with a [CancellationException].
  void clearQueue({String reason = 'Queue purged'}) {
    while (_queue.isNotEmpty) {
      final task = _queue.removeFirst();
      if (!task.completer.isCompleted) {
        task.completer.completeError(
          TimeoutException('Task cancelled before execution: $reason'),
        );
      }
    }
  }
}
