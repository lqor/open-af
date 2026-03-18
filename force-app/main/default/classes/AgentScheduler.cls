global without sharing class AgentScheduler implements Schedulable {
    global Id taskId;

    global AgentScheduler() {
    }

    global AgentScheduler(Id taskId) {
        this.taskId = taskId;
    }

    global void execute(SchedulableContext context) {
        if (taskId == null) {
            return;
        }
        AgentScheduleService.enqueueTaskRun(taskId);
    }
}
