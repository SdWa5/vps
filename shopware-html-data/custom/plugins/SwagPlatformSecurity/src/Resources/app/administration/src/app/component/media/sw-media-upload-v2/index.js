/**
 * @package discovery
 */
Shopware.Component.override('sw-media-upload-v2', {
    methods: {
        handleMediaServiceUploadEvent({ action, payload }) {
            if (action !== 'media-upload-fail') {
                return;
            }

            this.createNotificationError({
                title: this.$t('global.default.error'),
                message: this.getUploadFailureMessage(payload),
            });

            this.onRemoveMediaItem();
        },

        getUploadFailureMessage(task) {
            const detail = task?.error?.response?.data?.errors?.[0]?.detail;

            if (typeof detail === 'string' && detail.length > 0) {
                return detail;
            }

            return this.$t('global.sw-media-upload-v2.notification.failure.message');
        },
    },
});
