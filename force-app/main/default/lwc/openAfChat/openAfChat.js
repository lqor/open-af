import { LightningElement } from 'lwc';
import getBootstrap from '@salesforce/apex/OpenAfController.getBootstrap';
import submitPrompt from '@salesforce/apex/OpenAfController.submitPrompt';
import getConversationState from '@salesforce/apex/OpenAfController.getConversationState';
import cancelRun from '@salesforce/apex/OpenAfController.cancelRun';

const POLL_INTERVAL_MS = 2000;

export default class OpenAfChat extends LightningElement {
    bootstrapLoaded = false;
    messages = [];
    toolExecutions = [];
    currentConversationId;
    selectedConfigId;
    currentRunId;
    runStatus;
    prompt = '';
    error;
    pollHandle;
    pendingPrompt;

    connectedCallback() {
        this.loadBootstrap();
    }

    disconnectedCallback() {
        if (this.pollHandle) {
            window.clearTimeout(this.pollHandle);
            this.pollHandle = null;
        }
    }

    get isBusy() {
        return this.runStatus === 'Queued' || this.runStatus === 'Running';
    }

    get canCancel() {
        return Boolean(this.currentRunId) && this.isBusy;
    }

    get runStatusLabel() {
        return this.runStatus ? `Run: ${this.runStatus}` : 'Run: idle';
    }

    get hasMessages() {
        return this.displayMessages.length > 0;
    }

    get hasToolExecutions() {
        return this.toolExecutions.length > 0;
    }

    get transcriptSubtitle() {
        if (this.error) {
            return 'Something went sideways. Adjust the prompt and try again.';
        }
        if (this.isBusy) {
            return 'Open AF is working through the request. Your message is already queued.';
        }
        if (this.hasMessages) {
            return `${this.displayMessages.length} messages in this chat.`;
        }
        return 'Ask about records, schema, or setup details and let the agent do the digging.';
    }

    get toolTraceLabel() {
        return `Tool Trace${this.hasToolExecutions ? ` (${this.toolExecutions.length})` : ''}`;
    }

    get promptSuggestions() {
        return [
            'Show me the newest opportunities in this org.',
            'Describe the Account object in plain English.',
            'List the first 5 Contacts with names and emails.'
        ];
    }

    get displayMessages() {
        const rendered = this.messages.map((message) => this.decorateMessage(message));
        if (this.pendingPrompt) {
            rendered.push(this.decorateMessage({
                id: 'pending-user',
                role: 'user',
                content: this.pendingPrompt
            }));
        }
        if (this.isBusy) {
            rendered.push(this.decorateMessage({
                id: 'pending-assistant',
                role: 'assistant',
                content: 'Working on it...'
            }));
        }
        return rendered;
    }

    async loadBootstrap() {
        try {
            const data = await getBootstrap();
            const configs = data.configs || [];
            this.selectedConfigId = this.selectedConfigId || this.findActiveConfigId(configs);
            this.resetConversation();
            this.bootstrapLoaded = true;
        } catch (error) {
            this.error = this.getErrorMessage(error);
        }
    }

    findActiveConfigId(configs) {
        const active = configs.find((config) => config.active);
        return active ? active.id : configs[0]?.id;
    }

    applyConversationState(state) {
        if (!state) {
            return;
        }
        this.currentConversationId = state.conversationId;
        this.currentRunId = state.currentRunId;
        this.runStatus = state.runStatus;
        this.error = state.error;
        this.messages = state.messages || [];
        this.toolExecutions = state.toolExecutions || [];
        if (!this.isBusy) {
            this.pendingPrompt = null;
        }
    }

    async refreshConversation() {
        if (!this.currentConversationId) {
            return;
        }
        if (this.pollHandle) {
            window.clearTimeout(this.pollHandle);
            this.pollHandle = null;
        }
        try {
            const state = await getConversationState({ conversationId: this.currentConversationId });
            this.applyConversationState(state);
            if (state.runStatus === 'Queued' || state.runStatus === 'Running') {
                this.pollHandle = window.setTimeout(() => this.refreshConversation(), POLL_INTERVAL_MS);
            }
        } catch (error) {
            this.error = this.getErrorMessage(error);
        }
    }

    handlePromptChange(event) {
        this.prompt = event.target.value;
    }

    handlePromptKeydown(event) {
        if ((event.metaKey || event.ctrlKey) && event.key === 'Enter' && !this.isBusy) {
            event.preventDefault();
            this.handleSend();
        }
    }

    handleNewConversation() {
        this.resetConversation();
    }

    handleSuggestionClick(event) {
        const prompt = event.currentTarget.dataset.prompt;
        this.prompt = prompt;
        const textarea = this.template.querySelector('lightning-textarea');
        if (textarea) {
            textarea.value = prompt;
            textarea.focus();
        }
    }

    async handleSend() {
        const promptInput = this.template.querySelector('lightning-textarea');
        const promptValue = (promptInput?.value ?? this.prompt ?? '').trim();
        if (!promptValue) {
            return;
        }

        this.error = null;
        this.pendingPrompt = promptValue;
        this.prompt = '';
        if (promptInput) {
            promptInput.value = '';
        }
        try {
            const result = await submitPrompt({
                request: {
                    conversationId: this.currentConversationId,
                    configId: this.selectedConfigId,
                    prompt: promptValue,
                    triggerType: 'chat'
                }
            });
            this.currentConversationId = result.conversationId;
            this.currentRunId = result.runId;
            this.runStatus = result.status;
            await this.refreshConversation();
        } catch (error) {
            this.pendingPrompt = null;
            this.error = this.getErrorMessage(error);
        }
    }

    async handleCancelRun() {
        if (!this.currentRunId) {
            return;
        }
        try {
            await cancelRun({ runId: this.currentRunId });
            this.pendingPrompt = null;
            await this.refreshConversation();
        } catch (error) {
            this.error = this.getErrorMessage(error);
        }
    }

    resetConversation() {
        if (this.pollHandle) {
            window.clearTimeout(this.pollHandle);
            this.pollHandle = null;
        }
        this.currentConversationId = null;
        this.currentRunId = null;
        this.runStatus = null;
        this.messages = [];
        this.toolExecutions = [];
        this.prompt = '';
        this.pendingPrompt = null;
        this.error = null;
    }

    decorateMessage(message) {
        return {
            ...message,
            roleLabel: (message.role || 'assistant').toUpperCase(),
            className: `message message-${message.role || 'assistant'}`
        };
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }
}
