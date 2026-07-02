<?php declare(strict_types=1);

namespace Swag\Security;

use Shopware\Core\Framework\Log\Package;
use Shopware\Core\Framework\Plugin;
use Shopware\Core\Kernel;
use Swag\Security\Components\AbstractSecurityFix;
use Swag\Security\Components\RemoveDisabledServicesCompilerPass;
use Swag\Security\DependencyInjection\Configuration;
use Swag\Security\DependencyInjection\FrameworkExtension;
use Symfony\Component\DependencyInjection\ContainerBuilder;
use Symfony\Component\DependencyInjection\ContainerInterface;
use Symfony\Component\DependencyInjection\Extension\ExtensionInterface;

#[Package('framework')]
class SwagPlatformSecurity extends Plugin
{
    final public const PLUGIN_NAME = 'SwagPlatformSecurity';

    public function build(ContainerBuilder $container): void
    {
        parent::build($container);

        $this->fetchPluginConfig($container);
        $container->addCompilerPass(new RemoveDisabledServicesCompilerPass());
    }

    public function getContainerExtension(): ?ExtensionInterface
    {
        // Decide if we should override the Shopware config because we have a missing configuration
        $shouldOverrideShopwareConfig = !Configuration::hasSearchSection();

        if ($shouldOverrideShopwareConfig) {
            return new FrameworkExtension();
        }

        return null;
    }

    public function boot(): void
    {
        parent::boot();

        \assert($this->container instanceof ContainerInterface, 'Container is not set yet, please call setContainer() before calling boot(), see `platform/Core/Kernel.php:186`.');

        foreach ($this->container->getParameter('SwagPlatformSecurity.activeFixes') as $securityFix) {
            $securityFix::boot($this->container);
        }
    }

    public function getTemplatePriority(): int
    {
        // same template priority as the core bundles,
        // plugin templates should only have a prio of 0 or higher and be loaded after the core templates
        return -1;
    }

    private function fetchPluginConfig(ContainerBuilder $container): void
    {
        try {
            $config = Kernel::getConnection()->fetchAllKeyValue('SELECT ticket, active FROM swag_security_config');
        } catch (\Throwable) {
            $config = [];
        }

        foreach ($config as &$item) {
            $item = (bool) $item;
        }
        unset($item);

        $shopwareVersion = $_SERVER['SHOPWARE_FAKE_VERSION'] ?? $container->getParameter('kernel.shopware_version');
        /** @var list<class-string<AbstractSecurityFix>> $knownIssues */
        $knownIssues = $container->getParameter('SwagPlatformSecurity.knownIssues');
        $availableFixes = [];
        $activeFixes = [];

        foreach ($knownIssues as $knownIssue) {
            if (!$knownIssue::isValidForVersion($shopwareVersion)) {
                continue;
            }

            $availableFixes[] = $knownIssue;

            if (\array_key_exists($knownIssue::getTicket(), $config) && !$config[$knownIssue::getTicket()]) {
                continue;
            }

            $knownIssue::buildContainer($container);

            $activeFixes[] = $knownIssue;
        }

        $container->setParameter('SwagPlatformSecurity.activeFixes', $activeFixes);
        $container->setParameter('SwagPlatformSecurity.availableFixes', $availableFixes);
    }
}
