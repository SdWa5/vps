<?php declare(strict_types=1);

namespace Swag\Security\Twig;

use Symfony\Component\Routing\Exception\RouteNotFoundException;
use Symfony\Component\Routing\Generator\UrlGeneratorInterface;
use Twig\Extension\AbstractExtension;
use Twig\TwigFunction;

class RouteExistsTwigExtension extends AbstractExtension
{
    public function __construct(
        private readonly UrlGeneratorInterface $generator,
    ) {
    }

    /**
     * @return list<TwigFunction>
     */
    public function getFunctions(): array
    {
        return [
            new TwigFunction('route_exists', $this->routeExists(...)),
        ];
    }

    public function routeExists(string $routeName): bool
    {
        try {
            $this->generator->generate($routeName);
        } catch (RouteNotFoundException) {
            return false;
        } catch (\Throwable) {
            // ignore other exception, e.g. when params are missing
            // RouteNotFoundException is thrown first, when we get another exception, we can assume the route exists
            return true;
        }

        return true;
    }
}
