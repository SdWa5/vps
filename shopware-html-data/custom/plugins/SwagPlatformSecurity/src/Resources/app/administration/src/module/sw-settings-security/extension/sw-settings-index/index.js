import template from './sw-settings-index.html.twig';

/**
 * @package framework
 */
Shopware.Component.override('sw-settings-index', {
    template,

    inject: ['acl'],
});
