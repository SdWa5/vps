const ApiService = Shopware.Classes.ApiService;

/**
 * @package framework
 */
export default class SwagSecurityApiClient extends ApiService {
    constructor(httpClient, loginService, apiEndpoint = 'swag-security') {
        super(httpClient, loginService, apiEndpoint);
    }

    getFixes() {
        return this.httpClient
            .get(`_action/${this.getApiBasePath()}/available-fixes`, {
                headers: this.getBasicHeaders({}),
            })
            .then(ApiService.handleResponse);
    }

    saveValues(config, currentPassword) {
        return this.httpClient
            .post(
                `_action/${this.getApiBasePath()}/save-config`,
                { config, currentPassword },
                { headers: this.getBasicHeaders({}) },
            )
            .then(ApiService.handleResponse);
    }

    cacheClear() {
        return this.httpClient
            .delete(`_action/${this.getApiBasePath()}/clear-container-cache`, {
                headers: this.getBasicHeaders({}),
            })
            .then(ApiService.handleResponse);
    }
}
