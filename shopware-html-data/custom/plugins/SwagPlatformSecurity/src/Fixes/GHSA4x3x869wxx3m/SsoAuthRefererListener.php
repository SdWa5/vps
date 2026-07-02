<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA4x3x869wxx3m;

use Shopware\Core\DevOps\Environment\EnvironmentHelper;
use Shopware\Core\Framework\Log\Package;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\RequestEvent;
use Symfony\Component\HttpKernel\KernelEvents;
use Symfony\Component\Routing\Exception\RouteNotFoundException;
use Symfony\Component\Routing\Generator\UrlGeneratorInterface;
use Symfony\Component\Routing\RouterInterface;

/**
 * GHSA-4x3x-869w-xx3m: mitigates the open redirect on /api/oauth/sso/auth.
 *
 * The upstream SsoController falls back to the Referer header when the SSO
 * session state is missing. This listener overwrites the Referer header on
 * that route with a fixed internal admin URL so the fallback can only redirect
 * to a trusted destination.
 */
#[Package('framework')]
class SsoAuthRefererListener implements EventSubscriberInterface
{
    public function __construct(private readonly RouterInterface $router)
    {
    }

    public static function getSubscribedEvents(): array
    {
        return [KernelEvents::REQUEST => 'onKernelRequest'];
    }

    public function onKernelRequest(RequestEvent $event): void
    {
        if (!$event->isMainRequest()) {
            return;
        }

        $request = $event->getRequest();
        if ($request->attributes->get('_route') !== 'oauth.sso.auth') {
            return;
        }

        try {
            $url = $this->router->generate('administration.index', [], UrlGeneratorInterface::ABSOLUTE_URL);
        } catch (RouteNotFoundException) {
            $url = EnvironmentHelper::getVariable('APP_URL') . '/admin';
        }

        $request->headers->set('referer', $url);
    }
}
