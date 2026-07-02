/**
 * @package framework
 */
export default class SwagSecurityState {
    isActive(ticket) {
        return Shopware.State.get('context').app.config.swagSecurity.includes(ticket);
    }
}
