<?php declare(strict_types=1);

namespace Swag\Security\Twig;

use Shopware\Core\Framework\Adapter\Twig\NamespaceHierarchy\TemplateNamespaceHierarchyBuilderInterface;
use Shopware\Core\Framework\Parameter\AdditionalBundleParameters;
use Shopware\Core\Framework\Plugin;
use Shopware\Core\Framework\Plugin\KernelPluginLoader\KernelPluginLoader;
use Swag\Security\Components\State;
use Swag\Security\Fixes\GHSAh2x3h9qrcf82\CheckSubscriptionCustomerCSRF;
use Swag\Security\SwagPlatformSecurity;
use Symfony\Component\HttpKernel\KernelInterface;

class SecurityNamespaceHierarchyBuilder implements TemplateNamespaceHierarchyBuilderInterface
{
    private const COMMERCIAL_BUNDLE_NAME = 'SwagCommercial';

    private const COMMERCIAL_TEMPLATE_FIXES = [
        /** @see CheckSubscriptionCustomerCSRF */
        'GHSA-h2x3-h9qr-cf82',
    ];

    public function __construct(
        private readonly KernelInterface $kernel,
        private readonly KernelPluginLoader $pluginLoader,
        private readonly State $state
    ) {
    }

    /**
     * we might need to override commercial templates as well,
     * however usually commercial templates have higher priority than security templates
     * so we need to move the commercial bundle names between the security bundle and the core templates in the hierarchy
     * we only do this if fixes are active that need that, to add fixes add them to the COMMERCIAL_TEMPLATE_FIXES constant
     */
    public function buildNamespaceHierarchy(array $namespaceHierarchy): array
    {
        $needsToBeApplied = false;
        foreach (self::COMMERCIAL_TEMPLATE_FIXES as $fix) {
            if ($this->state->isActive($fix)) {
                $needsToBeApplied = true;
            }
        }

        // early return if all fixes that need to overwrite commercial templates are not active
        if (!$needsToBeApplied) {
            return $namespaceHierarchy;
        }

        $oldHierarchy = $namespaceHierarchy;

        try {
            $commercial = $this->kernel->getBundle(self::COMMERCIAL_BUNDLE_NAME);
        } catch (\InvalidArgumentException $e) {
            // commercial plugin is not installed, nothing to do
            return $namespaceHierarchy;
        }

        \assert($commercial instanceof Plugin);
        $commercialBundles = $commercial->getAdditionalBundles(
            new AdditionalBundleParameters(
                $this->pluginLoader->getClassLoader(),
                $this->pluginLoader->getPluginInstances(),
                []
            )
        );

        $commercialHierarchy = [];

        foreach ($commercialBundles as $bundle) {
            if (!\array_key_exists($bundle->getName(), $namespaceHierarchy)) {
                continue;
            }

            // remove commercial bundle from hierarchy and build own hierarchy with priority -1
            $commercialHierarchy[$bundle->getName()] = -1;
            unset($namespaceHierarchy[$bundle->getName()]);
        }

        // find position of security bundle in hierarchy
        $securityIndex = array_search(SwagPlatformSecurity::PLUGIN_NAME, array_keys($namespaceHierarchy), true);
        if ($securityIndex === false) {
            return $oldHierarchy;
        }

        // split the array after security bundle
        $beforeSecurity = \array_slice($namespaceHierarchy, 0, $securityIndex + 1);
        $afterSecurity = \array_slice($namespaceHierarchy, $securityIndex + 1);

        // merge arrays and insert commercial bundles right after security bundle
        return array_merge($beforeSecurity, $commercialHierarchy, $afterSecurity);
    }
}
