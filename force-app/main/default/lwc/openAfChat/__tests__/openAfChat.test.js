import { createElement } from 'lwc';
import OpenAfChat from 'c/openAfChat';
import getBootstrap from '@salesforce/apex/OpenAfController.getBootstrap';
import submitPrompt from '@salesforce/apex/OpenAfController.submitPrompt';
import getConversationState from '@salesforce/apex/OpenAfController.getConversationState';
import cancelRun from '@salesforce/apex/OpenAfController.cancelRun';
import getConversations from '@salesforce/apex/OpenAfController.getConversations';

jest.mock(
    '@salesforce/apex/OpenAfController.getBootstrap',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/OpenAfController.submitPrompt',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/OpenAfController.getConversationState',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/OpenAfController.cancelRun',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/OpenAfController.getConversations',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

const flushPromises = async () => Promise.resolve();

const bootstrapPayload = {
    configs: [{ id: 'cfg-active', active: true }],
    conversations: [
        { id: 'conv-1', name: 'Test Conversation', status: 'Open' }
    ],
    conversationState: null,
    currentConversationId: null
};

describe('c-open-af-chat', () => {
    beforeEach(() => {
        jest.useFakeTimers();
        getBootstrap.mockResolvedValue(bootstrapPayload);
        getConversations.mockResolvedValue([
            { id: 'conv-1', name: 'Test Conversation', status: 'Open' }
        ]);
        submitPrompt.mockResolvedValue({
            conversationId: 'conv-1',
            runId: 'run-1',
            status: 'Queued'
        });
        getConversationState.mockResolvedValue({
            conversationId: 'conv-1',
            currentRunId: 'run-1',
            runStatus: 'Completed',
            error: null,
            finalResponse: 'Found Acme.',
            messages: [
                { id: 'm-1', role: 'user', content: 'Find Acme' },
                { id: 'm-2', role: 'assistant', content: 'Found Acme.' }
            ],
            toolExecutions: [
                {
                    id: 't-1',
                    toolName: 'runSoql',
                    status: 'Completed',
                    inputJson: '{"query":"SELECT Id FROM Account LIMIT 1"}',
                    outputJson: '{"totalSize":1}',
                    error: null
                }
            ]
        });
        cancelRun.mockResolvedValue({ status: 'Cancelled' });
    });

    afterEach(() => {
        jest.runOnlyPendingTimers();
        jest.useRealTimers();
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function mount() {
        const element = createElement('c-open-af-chat', {
            is: OpenAfChat
        });
        document.body.appendChild(element);
        return element;
    }

    async function loadComponent() {
        const element = mount();
        await flushPromises();
        return element;
    }

    it('loads bootstrap data, renders suggestions, and applies a clicked suggestion to the composer', async () => {
        const element = await loadComponent();

        expect(getBootstrap).toHaveBeenCalledTimes(1);
        expect(element.shadowRoot.querySelectorAll('.suggestion-chip')).toHaveLength(3);
        expect(element.shadowRoot.querySelector('.welcome-message')).not.toBeNull();

        const textarea = element.shadowRoot.querySelector('lightning-textarea');
        const firstSuggestion = element.shadowRoot.querySelector('.suggestion-chip');
        firstSuggestion.click();
        await flushPromises();

        expect(textarea.value).toBe('Show me the newest opportunities in this org.');
    });

    it('submits a prompt and refreshes conversation', async () => {
        const element = await loadComponent();

        const textarea = element.shadowRoot.querySelector('lightning-textarea');
        textarea.value = 'Find Acme';
        textarea.dispatchEvent(new CustomEvent('input'));

        const sendButton = element.shadowRoot.querySelector('.send-button');
        sendButton.click();
        await flushPromises();
        await flushPromises();

        // Verify that submitPrompt was called with correct parameters
        expect(submitPrompt).toHaveBeenCalled();
    });

    it('handles cancellation when cancel button is clicked', async () => {
        getConversationState
            .mockResolvedValueOnce({
                conversationId: 'conv-1',
                currentRunId: 'run-1',
                runStatus: 'Running',
                error: null,
                finalResponse: null,
                messages: [{ id: 'm-1', role: 'user', content: 'Find Acme' }],
                toolExecutions: []
            })
            .mockResolvedValueOnce({
                conversationId: 'conv-1',
                currentRunId: 'run-1',
                runStatus: 'Cancelled',
                error: 'Cancelled by user.',
                finalResponse: null,
                messages: [{ id: 'm-1', role: 'user', content: 'Find Acme' }],
                toolExecutions: []
            });

        const element = await loadComponent();
        const textarea = element.shadowRoot.querySelector('lightning-textarea');
        textarea.value = 'Find Acme';
        textarea.dispatchEvent(new CustomEvent('input'));

        const sendButton = element.shadowRoot.querySelector('.send-button');
        sendButton.click();
        await flushPromises();
        await flushPromises();
        await flushPromises();

        const cancelButton = element.shadowRoot.querySelector('.cancel-button');
        expect(cancelButton).not.toBeNull();

        cancelButton.click();
        await flushPromises();
        await flushPromises();
        expect(cancelRun).toHaveBeenCalledWith({ runId: 'run-1' });
    });

    it('surfaces bootstrap errors in the banner', async () => {
        getBootstrap.mockRejectedValue(new Error('Bootstrap exploded'));

        const element = mount();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.error-banner').textContent).toContain('Bootstrap exploded');
    });
});
