<?php declare(strict_types=1);

namespace Swag\Security\Api;

use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\State;
use Symfony\Component\Filesystem\Filesystem;
use Symfony\Component\Finder\Finder;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

#[Route(defaults: ['_routeScope' => ['api']])]
#[Package('framework')]
class SecurityController
{
    public function __construct(
        private readonly State $state,
        private readonly string $cacheDir,
    ) {
    }

    #[Route(path: '/api/_action/swag-security/available-fixes')]
    public function getFixes(): JsonResponse
    {
        return new JsonResponse([
            'availableFixes' => array_map(static fn ($fix) => $fix::getTicket(), $this->state->getAvailableFixes()),
            'activeFixes' => array_map(static fn ($fix) => $fix::getTicket(), $this->state->getActiveFixes()),
        ]);
    }

    #[Route(path: '/api/_action/swag-security/clear-container-cache')]
    public function clearContainerCache(): Response
    {
        $finder = (new Finder())->in($this->cacheDir)->name('*Container*')->depth(0);
        $containerCaches = [];

        foreach ($finder->getIterator() as $containerPaths) {
            $containerCaches[] = $containerPaths->getRealPath();
        }

        (new Filesystem())->remove($containerCaches);

        return new Response('', Response::HTTP_NO_CONTENT);
    }
}
