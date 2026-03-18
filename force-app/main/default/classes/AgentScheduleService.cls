public without sharing class AgentScheduleService {
    public static ScheduledTask__c saveScheduledTask(OpenAfModels.ScheduledTaskInput input) {
        if (input == null) {
            throw new AuraHandledException('Scheduled task input is required.');
        }
        if (String.isBlank(input.name) || String.isBlank(input.prompt)) {
            throw new AuraHandledException('Task name and prompt are required.');
        }

        ScheduledTask__c task = input.id != null
            ? [
                SELECT Id, Name, AgentConfig__c, Prompt__c, IsRecurring__c, CronExpression__c, OneOffRunAt__c, Status__c, JobId__c
                FROM ScheduledTask__c
                WHERE Id = :input.id
                LIMIT 1
            ]
            : new ScheduledTask__c();

        if (!String.isBlank(task.JobId__c)) {
            System.abortJob(task.JobId__c);
            task.JobId__c = null;
        }

        task.Name = input.name.trim();
        task.AgentConfig__c = input.agentConfigId == null ? AgentConfigService.getOrCreateDefaultConfig().Id : input.agentConfigId;
        task.Prompt__c = input.prompt.trim();
        task.IsRecurring__c = input.isRecurring == true;
        task.CronExpression__c = task.IsRecurring__c ? input.cronExpression : toOneOffCron(input.oneOffRunAt);
        task.OneOffRunAt__c = task.IsRecurring__c ? null : input.oneOffRunAt;
        task.Status__c = String.isBlank(input.status) ? 'Active' : input.status;

        if (String.isBlank(task.CronExpression__c)) {
            throw new AuraHandledException('Provide either a recurring cron expression or a one-off run datetime.');
        }

        if (task.Id == null) {
            insert task;
        } else {
            update task;
        }

        if (task.Status__c == 'Active') {
            String jobName = 'OpenAF-' + task.Id + '-' + DateTime.now().getTime();
            String jobId = System.schedule(jobName, task.CronExpression__c, new AgentScheduler(task.Id));
            task.JobId__c = jobId;
            update task;
        }
        return [
            SELECT Id, Name, AgentConfig__c, Prompt__c, IsRecurring__c, CronExpression__c, OneOffRunAt__c, Status__c, JobId__c, LastRunAt__c, LastRunStatus__c, CreatedDate
            FROM ScheduledTask__c
            WHERE Id = :task.Id
            LIMIT 1
        ];
    }

    public static void cancelScheduledTask(Id taskId) {
        ScheduledTask__c task = [
            SELECT Id, JobId__c, Status__c
            FROM ScheduledTask__c
            WHERE Id = :taskId
            LIMIT 1
        ];
        if (!String.isBlank(task.JobId__c)) {
            System.abortJob(task.JobId__c);
        }
        task.JobId__c = null;
        task.Status__c = 'Paused';
        update task;
    }

    public static void enqueueTaskRun(Id taskId) {
        ScheduledTask__c task = [
            SELECT Id, Name, AgentConfig__c, Prompt__c, IsRecurring__c, Status__c, JobId__c
            FROM ScheduledTask__c
            WHERE Id = :taskId
            LIMIT 1
        ];
        if (task.Status__c != 'Active') {
            return;
        }

        Conversation__c conversation = new Conversation__c(
            Name = 'Scheduled - ' + task.Name,
            AgentConfig__c = task.AgentConfig__c,
            Status__c = 'Open'
        );
        insert conversation;

        Run__c runRecord = new Run__c(
            Conversation__c = conversation.Id,
            AgentConfig__c = task.AgentConfig__c,
            ScheduledTask__c = task.Id,
            UserPrompt__c = task.Prompt__c,
            Status__c = 'Queued',
            TriggerType__c = 'schedule'
        );
        insert runRecord;
        System.enqueueJob(new AgentExecutor(runRecord.Id));

        if (!task.IsRecurring__c) {
            task.Status__c = 'Completed';
            task.JobId__c = null;
            update task;
        }
    }

    public static void markTaskRun(Id taskId, String status) {
        List<ScheduledTask__c> tasks = [
            SELECT Id, LastRunAt__c, LastRunStatus__c
            FROM ScheduledTask__c
            WHERE Id = :taskId
            LIMIT 1
        ];
        if (tasks.isEmpty()) {
            return;
        }
        ScheduledTask__c task = tasks[0];
        task.LastRunAt__c = System.now();
        task.LastRunStatus__c = status;
        update task;
    }

    public static List<OpenAfModels.ScheduledTaskView> getScheduledTaskViews() {
        List<OpenAfModels.ScheduledTaskView> views = new List<OpenAfModels.ScheduledTaskView>();
        for (ScheduledTask__c task : [
            SELECT Id, Name, AgentConfig__c, Prompt__c, IsRecurring__c, CronExpression__c, OneOffRunAt__c, Status__c, JobId__c, LastRunAt__c, LastRunStatus__c, CreatedDate
            FROM ScheduledTask__c
            ORDER BY CreatedDate DESC
            LIMIT 100
        ]) {
            OpenAfModels.ScheduledTaskView view = new OpenAfModels.ScheduledTaskView();
            view.id = task.Id;
            view.name = task.Name;
            view.agentConfigId = task.AgentConfig__c;
            view.prompt = task.Prompt__c;
            view.isRecurring = task.IsRecurring__c;
            view.cronExpression = task.CronExpression__c;
            view.oneOffRunAt = task.OneOffRunAt__c;
            view.status = task.Status__c;
            view.jobId = task.JobId__c;
            view.lastRunAt = task.LastRunAt__c;
            view.lastRunStatus = task.LastRunStatus__c;
            view.createdDate = task.CreatedDate;
            views.add(view);
        }
        return views;
    }

    private static String toOneOffCron(Datetime runAt) {
        if (runAt == null) {
            return null;
        }
        Datetime scheduled = runAt;
        return String.format(
            '0 {0} {1} {2} {3} ? {4}',
            new List<String>{
                String.valueOf(scheduled.minute()),
                String.valueOf(scheduled.hour()),
                String.valueOf(scheduled.day()),
                String.valueOf(scheduled.month()),
                String.valueOf(scheduled.year())
            }
        );
    }
}
