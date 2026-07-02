<?php declare(strict_types=1);

namespace Swag\Security\Subscriber;

use Shopware\Core\Framework\Api\Event\AdminInfoConfigEvent;
use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;
use Swag\Security\Components\State;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Event\ResponseEvent;

#[Package('framework')]
readonly class AdminSecurityFixesProvider implements EventSubscriberInterface
{
    public function __construct(private State $state)
    {
    }

    public static function getSubscribedEvents(): array
    {
        if (class_exists(AdminInfoConfigEvent::class)) {
            return [
                AdminInfoConfigEvent::class => 'addSecurityFixesOnEvent',
            ];
        }

        return [
            ResponseEvent::class => 'addSecurityFixesOnResponse',
        ];
    }

    /**
     * @deprecated tag:v6.8.0 - Can be removed once the minimum required version of Shopware contains `AdminInfoConfigEvent`
     */
    public function addSecurityFixesOnResponse(ResponseEvent $event): void
    {
        if ($event->getRequest()->attributes->get('_route') !== 'api.info.config') {
            return;
        }

        $response = $event->getResponse();
        // Do not extend the response if there was an error
        if (!$response instanceof JsonResponse || !$response->isSuccessful()) {
            return;
        }

        $config = $response->getContent();
        if (!\is_string($config)) {
            return;
        }

        $config = json_decode($config, true, 512, \JSON_THROW_ON_ERROR);
        $config['swagSecurity'] = $this->getFixIdentifiers();

        $response->setData($config);
    }

    public function addSecurityFixesOnEvent(object $event): void
    {
        /** @phpstan-ignore method.notFound (Change parameter type to `AdminInfoConfigEvent` once the minimum required version of Shopware contains it) */
        $event->addConfig('swagSecurity', $this->getFixIdentifiers());
    }

    /**
     * @return list<string>
     */
    private function getFixIdentifiers(): array
    {
        return array_values(array_map(static function (string $fix): string {
            /** @var class-string<AbstractSecurityFix> $fix */
            return $fix::getTicket();
        }, $this->state->getActiveFixes()));
    }
}
