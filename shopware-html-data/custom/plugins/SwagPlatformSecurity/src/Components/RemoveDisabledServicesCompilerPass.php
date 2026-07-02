<?php declare(strict_types=1);

namespace Swag\Security\Components;

use Shopware\Core\Framework\Log\Package;
use Symfony\Component\DependencyInjection\Compiler\CompilerPassInterface;
use Symfony\Component\DependencyInjection\ContainerBuilder;

#[Package('framework')]
class RemoveDisabledServicesCompilerPass implements CompilerPassInterface
{
    public function process(ContainerBuilder $container): void
    {
        $services = $container->findTaggedServiceIds('swag.security.fix');
        $activeFixes = $container->getParameter('SwagPlatformSecurity.activeFixes');

        foreach ($services as $id => $tag) {
            if (isset($tag[0]['ticket'])) {
                $ticket = $tag[0]['ticket'];
            } else {
                $ticket = $id::getTicket();
            }

            if (!\in_array($ticket, $activeFixes, true)) {
                $container->removeDefinition($id);
            }
        }
    }
}
