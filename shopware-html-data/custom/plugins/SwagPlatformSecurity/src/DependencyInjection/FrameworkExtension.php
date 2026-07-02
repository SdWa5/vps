<?php declare(strict_types=1);

namespace Swag\Security\DependencyInjection;

use Symfony\Component\DependencyInjection\ContainerBuilder;
use Symfony\Component\DependencyInjection\Extension\Extension;

class FrameworkExtension extends Extension
{
    private const ALIAS = 'shopware';

    /**
     * {@inheritdoc}
     */
    public function getAlias(): string
    {
        return self::ALIAS;
    }

    public function load(array $configs, ContainerBuilder $container): void
    {
        // Make sure the configuration is loaded
        array_unshift($configs, [
            'search' => [
                'term_max_length' => 300,
            ],
        ]);

        $config = $this->processConfiguration(new Configuration(), $configs);
        $this->addShopwareConfig($container, $this->getAlias(), $config);
    }

    /**
     * @param array<string, mixed> $options
     */
    private function addShopwareConfig(ContainerBuilder $container, string $alias, array $options): void
    {
        foreach ($options as $key => $option) {
            $key = $alias . '.' . $key;
            $container->setParameter($key, $option);

            if ($key === 'shopware.api.api_browser.auth_required') {
                $container->setParameter('shopware.api.api_browser.auth_required_str', (string) (int) $option);
            }

            if (\is_array($option)) {
                $this->addShopwareConfig($container, $key, $option);
            }
        }
    }
}
