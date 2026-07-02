import SwagSecurityApiClient from '../service/swagSecurityApiClient';
import SwagSecurityState from '../service/swagSecurityState';

Shopware.Application.addServiceProvider('swagSecurityApi', (container) => {
    const initContainer = Shopware.Application.getContainer('init');
    return new SwagSecurityApiClient(initContainer.httpClient, container.loginService);
});

Shopware.Application.addServiceProvider('swagSecurityState', () => {
    return new SwagSecurityState();
});
