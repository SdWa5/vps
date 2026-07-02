<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAv39m97p8gqg7;

use Shopware\Core\Framework\Api\Context\AdminApiSource;
use Shopware\Core\Framework\Api\Controller\Exception\PermissionDeniedException;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\Log\Package;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\ControllerArgumentsEvent;
use Symfony\Component\HttpKernel\KernelEvents;

/**
 * GHSA-v39m-97p8-gqg7: blocks privilege escalation via the "admin" body field
 * on POST /api/user and PATCH /api/user/{id} for non-admin sources.
 */
#[Package('fundamentals@framework')]
class UpsertUserAdminFieldListener implements EventSubscriberInterface
{
    private const PROTECTED_ROUTES = ['api.user.create', 'api.user.update'];

    public static function getSubscribedEvents(): array
    {
        return [KernelEvents::CONTROLLER_ARGUMENTS => 'onKernelControllerArguments'];
    }

    public function onKernelControllerArguments(ControllerArgumentsEvent $event): void
    {
        if (!$event->isMainRequest()) {
            return;
        }

        $request = $event->getRequest();
        if (!\in_array($request->attributes->get('_route'), self::PROTECTED_ROUTES, true)) {
            return;
        }

        if (!$request->request->has('admin')) {
            return;
        }

        $context = null;
        foreach ($event->getArguments() as $argument) {
            if ($argument instanceof Context) {
                $context = $argument;
                break;
            }
        }

        if ($context === null) {
            return;
        }

        $source = $context->getSource();
        if ($source instanceof AdminApiSource && $source->isAdmin()) {
            return;
        }

        throw new PermissionDeniedException();
    }
}
