import { LightningElement } from 'lwc';
import getBootstrap from '@salesforce/apex/OpenAfController.getBootstrap';
import submitPrompt from '@salesforce/apex/OpenAfController.submitPrompt';
import getConversationState from '@salesforce/apex/OpenAfController.getConversationState';
import cancelRun from '@salesforce/apex/OpenAfController.cancelRun';
import getConversations from '@salesforce/apex/OpenAfController.getConversations';

const POLL_INTERVAL_MS = 2000;

export default class OpenAfChat extends LightningElement {
    bootstrapLoaded = false;
    conversations = [];
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
    showToolTrace = false;
    resizeHandler;

    connectedCallback() {
        this.resizeHandler = () => this.updateAvailableHeight();
        window.addEventListener('resize', this.resizeHandler);
        this.loadBootstrap();
    }

    renderedCallback() {
        this.updateAvailableHeight();
    }

    disconnectedCallback() {
        if (this.pollHandle) {
            window.clearTimeout(this.pollHandle);
            this.pollHandle = null;
        }
        if (this.resizeHandler) {
            window.removeEventListener('resize', this.resizeHandler);
            this.resizeHandler = null;
        }
    }

    get isBusy() {
        return this.runStatus === 'Queued' || this.runStatus === 'Running';
    }

    get canCancel() {
        return Boolean(this.currentRunId) && this.isBusy;
    }

    get isSendDisabled() {
        return this.isBusy;
    }

    get toolTraceButtonLabel() {
        return this.showToolTrace ? 'Hide' : 'Show';
    }

    get hasMessages() {
        return this.displayMessages.length > 0;
    }

    get hasConversations() {
        return this.conversations.length > 0;
    }

    get hasToolExecutions() {
        return this.toolExecutions.length > 0;
    }

    get promptSuggestions() {
        return [
            'Show me the newest opportunities in this org.',
            'Describe the Account object in plain English.',
            'List the first 5 Contacts with names and emails.'
        ];
    }

    get displayMessages() {
        // Filter out tool calls by default, only show user and assistant messages
        const filtered = this.messages.filter(message => 
            message.role === 'user' || message.role === 'assistant'
        ).map(message => this.decorateMessage(message));

        if (this.pendingPrompt) {
            filtered.push(this.decorateMessage({
                id: 'pending-user',
                role: 'user',
                content: this.pendingPrompt
            }));
        }
        if (this.isBusy) {
            filtered.push(this.decorateMessage({
                id: 'pending-assistant',
                role: 'assistant',
                content: 'Working on it...'
            }));
        }
        return filtered;
    }

    async loadBootstrap() {
        try {
            const data = await getBootstrap();
            const configs = data.configs || [];
            this.selectedConfigId = this.selectedConfigId || this.findActiveConfigId(configs);
            this.conversations = (data.conversations || []).map(conv => ({
                ...conv,
                className: conv.id === this.currentConversationId ? 'active' : ''
            }));
            this.resetConversation();
            this.bootstrapLoaded = true;
        } catch (error) {
            this.error = this.getErrorMessage(error);
        }
    }

    async loadConversations() {
        try {
            const convs = await getConversations();
            this.conversations = (convs || []).map(conv => ({
                ...conv,
                className: conv.id === this.currentConversationId ? 'active' : ''
            }));
        } catch (error) {
            console.error('Failed to load conversations:', error);
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
        
        // Update active conversation in sidebar
        this.conversations = this.conversations.map(conv => ({
            ...conv,
            className: conv.id === this.currentConversationId ? 'active' : ''
        }));
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
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                this.pollHandle = window.setTimeout(() => this.refreshConversation(), POLL_INTERVAL_MS);
            }
        } catch (error) {
            this.error = this.getErrorMessage(error);
        }
    }

    handlePromptChange(event) {
        this.prompt = event?.detail?.value ?? event?.target?.value ?? '';
    }

    handlePromptKeydown(event) {
        if (event.key === 'Enter' && !event.shiftKey && !this.isBusy) {
            event.preventDefault();
            this.handleSend();
        }
    }

    handleNewConversation() {
        this.resetConversation();
    }

    handleConversationSelect(event) {
        const conversationId = event.currentTarget.dataset.id;
        if (conversationId && conversationId !== this.currentConversationId) {
            this.currentConversationId = conversationId;
            this.refreshConversation();
        }
    }

    handleSuggestionClick(event) {
        const prompt = event.currentTarget.dataset.prompt;
        this.prompt = prompt;
        const textarea = this.template.querySelector('.message-input');
        if (textarea) {
            textarea.value = prompt;
            textarea.focus();
        }
    }

    async handleSend() {
        const promptInput = this.template.querySelector('.message-input');
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
            await this.loadConversations();
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

    toggleToolTrace() {
        this.showToolTrace = !this.showToolTrace;
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
        this.showToolTrace = false;
        
        // Update active conversation in sidebar
        this.conversations = this.conversations.map(conv => ({
            ...conv,
            className: ''
        }));
    }

    decorateMessage(message) {
        const isToolCall = message.role === 'tool' || message.toolName;
        return {
            ...message,
            isToolCall,
            className: `message message-${message.role || 'assistant'}`
        };
    }

    updateAvailableHeight() {
        const page = this.template.querySelector('.page');
        if (!page) {
            return;
        }

        const top = page.getBoundingClientRect().top;
        const viewportHeight = window.innerHeight || document.documentElement.clientHeight;
        const paddingBottom = 16;
        const available = Math.max(448, Math.floor(viewportHeight - top - paddingBottom));

        this.template.host.style.setProperty('--openaf-available-height', `${available}px`);
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }
}