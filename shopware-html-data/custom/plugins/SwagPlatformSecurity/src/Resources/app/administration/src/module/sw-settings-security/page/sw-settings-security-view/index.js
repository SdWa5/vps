import template from './sw-settings-security-view.html.twig';
import './sw-settings-security-view.scss';

/**
 * @package framework
 */
Shopware.Component.register('sw-settings-security-view', {
    template,

    mixins: [Shopware.Mixin.getByName('notification')],

    inject: ['swagSecurityApi'],

    data() {
        return {
            isLoading: false,
            confirmPasswordModal: false,
            confirmPassword: '',
            config: {},
            fixes: [],
        };
    },

    async created() {
        await this.fetchFixes();
    },

    methods: {
        async fetchFixes() {
            this.isLoading = true;

            try {
                this.fixes = await this.swagSecurityApi.getFixes();

                this.config = this.fixes.availableFixes.reduce((acc, fix) => {
                    acc[fix] = this.fixes.activeFixes.includes(fix);
                    return acc;
                }, {});
            } catch {
                this.createNotificationError({
                    message: this.$tc('sw-settings-security.notification.fetchErrorMessage'),
                });
            } finally {
                this.isLoading = false;
            }
        },

        async onVerifiedSave() {
            this.isLoading = true;

            try {
                await this.swagSecurityApi.saveValues(this.config, this.confirmPassword);
                this.confirmPasswordModal = false;
                this.confirmPassword = '';

                await this.swagSecurityApi.cacheClear();
                await this.fetchFixes();
            } catch {
                this.createNotificationError({
                    title: this.$tc('sw-settings-security.notification.passwordErrorTitle'),
                    message: this.$tc('sw-settings-security.notification.passwordErrorMessage'),
                });
            } finally {
                this.isLoading = false;
            }
        },

        onCloseConfirmPasswordModal() {
            this.confirmPasswordModal = false;
            this.confirmPassword = '';
        },

        onSave() {
            this.confirmPasswordModal = true;
        },
    },
});
